# AI Tool-Calling Architecture

This document describes how MediFlow's AI chat assistant flows from the
client, through Gemini, to backend actions in Firestore, and the
authorization checks that guard that path.

## Overview

The AI chat assistant (`AIService.getChatResponse`) does not talk to Gemini
directly from the Flutter client. The client-side `ChatService` is disabled
by design (`isAvailable` always returns `false`) so that the Gemini API key
and all tool execution stay server-side. Instead, the client calls a single
Cloud Function, `getChatResponseSecure`, over Firebase Callable Functions.
That function owns the entire conversation with Gemini, including any
function/tool calls Gemini decides to make.

## Request flow

1. **Client -> Cloud Function.** The Flutter app calls the
   `getChatResponseSecure` callable with `query`, a `context` object built
   from local state (current inventory, role, etc.), the caller's `role`,
   and the chat `history`.
2. **Auth and facility resolution.** The function requires
   `request.auth` (Firebase Authentication) and calls
   `getUserFacilityAndRole` to resolve the caller to a role (`admin` or
   `facility_head`) and, for non-admins, a `facilityId`. If the caller's
   supplied `context.current_facility_id` does not match their resolved
   facility, the call is rejected with `permission-denied`.
3. **Rate limiting.** `checkRateLimit` is applied per-user before any
   Gemini call is made, using the shared `LIMITS.AI` policy.
4. **Prompt construction.** The function builds a single prompt containing
   a fixed "system blueprint" (the data model and business rules), the
   caller's `context`, and their `query`.
5. **Gemini call with tools.** A `gemini-1.5-flash` model is started with a
   `startChat` session seeded with the client-supplied `history`, and a
   `tools` declaration describing the callable functions (see below). The
   prompt is sent as the first message of that chat.
6. **Tool-call loop.** If Gemini's response contains one or more
   `functionCalls`, the function executes each one server-side via
   `executeTool(name, args, authInfo)`, collects the results, and sends them
   back to Gemini as `functionResponse` parts. This repeats until Gemini
   returns a response with no further function calls.
7. **Response to client.** The final text response from Gemini is returned
   to the Flutter client as a plain string.

If any step throws (quota errors, network errors, etc.), `AIService` falls
back to a local, non-AI response so the UI keeps working; forecasting and
smart alerts follow the same "try Gemini, fall back to local logic" pattern.

## Declared tools

`getChatResponseSecure` declares three functions to Gemini:

- `check_system_inventory` - no parameters. Returns current stock levels.
- `report_shortage` - `facilityId`, `medicineName`, `quantity`. Creates a
  pending shortage request.
- `report_surplus` - `facilityId`, `medicineName`, `quantity`. Creates a
  pending surplus request.

Gemini decides which of these (if any) to call based on the conversation;
it never executes them itself, it only asks the Cloud Function to.

## Tool execution and authorization

All tool execution goes through `executeTool`, which receives the resolved
`authInfo` (role and facility) computed earlier in the request, not
anything supplied by the client or by Gemini's arguments:

- `report_shortage` / `report_surplus`: the target `facilityId` in the
  tool arguments is checked against `authInfo.userFacilityId` unless the
  caller `isAdmin`. A non-admin cannot file a request on behalf of another
  facility, even if Gemini is persuaded to try. On success, a document is
  written to the `requests` collection with `status: "pending"`.
- `check_system_inventory`: non-admins only ever get their own facility's
  inventory, looked up by `authInfo.userFacilityId`. Admins get inventory
  across every facility. The scope is decided by `authInfo`, not by
  arguments Gemini supplies.

Any unrecognized function name throws, and the resulting error is passed
back to Gemini as a `functionResponse` error rather than crashing the
request, so a bad or hallucinated tool name degrades gracefully.

## Backend responsibilities summary

- **Client (`AIService`, `ChatService`):** collects context, calls the
  callable function, and falls back to local heuristics on failure. Never
  holds the Gemini API key and never executes tools itself.
- **`getChatResponseSecure`:** owns authentication, facility/role
  resolution, rate limiting, prompt construction, the Gemini chat session,
  and the function-calling loop.
- **`executeTool`:** the only place tool side effects happen; it re-checks
  authorization against the resolved caller identity before reading or
  writing Firestore data.
- **Firestore (`requests`, `inventory`, `facilities`):** the system of
  record that tool calls read from and write to.

## Related documentation

- [BigQuery integration](bigquery.md) documents how the same forecasting
  flow (`AIService.forecastDemand` and `logAIDecision`) is mirrored to
  BigQuery for auditability.
