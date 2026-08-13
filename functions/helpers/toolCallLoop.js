"use strict";

// Safety cap so a misbehaving model (or a tool that keeps asking for more
// tools) cannot spin the chat loop forever.
const MAX_TOOL_ROUNDS = 5;

/**
 * Drives the Gemini function-calling loop for a single chat turn.
 *
 * IMPORTANT: in the @google/generative-ai SDK, `response.functionCalls` is a
 * METHOD, not a getter — it must be invoked as `response.functionCalls()`.
 * Reading it as a property (`response.functionCalls`) returns the Function
 * object itself, which is always truthy and whose `.length` is the method's
 * declared parameter count (0), not the number of pending calls. That bug
 * made the round-trip below unreachable: `0 > 0` is always false, so tool
 * results were never sent back to the model and `response.text()` came back
 * empty on any turn where the model asked for a tool.
 *
 * @param {object} chat - A Gemini ChatSession (must expose sendMessage()).
 * @param {object} initialResult - Result of the first chat.sendMessage(prompt) call.
 * @param {(name: string, args: object) => Promise<object>} executeTool - Runs a
 *   single tool call and resolves with its result payload.
 * @param {number} [maxRounds] - Safety cap on tool-call rounds.
 * @returns {Promise<string>} The model's final text reply.
 * @throws {Error} If the model keeps requesting tools past maxRounds.
 */
async function runToolCallLoop(chat, initialResult, executeTool, maxRounds = MAX_TOOL_ROUNDS) {
    let result = initialResult;

    for (let round = 0; round < maxRounds; round++) {
        // functionCalls() is a method — must be invoked, not read as a property.
        const calls =
            typeof result.response.functionCalls === "function"
                ? result.response.functionCalls()
                : [];

        if (!calls || calls.length === 0) {
            return result.response.text();
        }

        const functionResponses = [];
        for (const call of calls) {
            let executionResult;
            try {
                executionResult = await executeTool(call.name, call.args);
            } catch (e) {
                executionResult = { error: e.message };
            }
            functionResponses.push({
                functionResponse: {
                    name: call.name,
                    response: executionResult,
                },
            });
        }

        result = await chat.sendMessage(functionResponses);
    }

    throw new Error("Tool call round limit exceeded");
}

module.exports = { runToolCallLoop, MAX_TOOL_ROUNDS };