/**
 * Unit tests for the Gemini tool-call loop (Issue #312)
 *
 * getChatResponseSecure previously read `response.functionCalls` as a
 * property instead of invoking it as a method, so executeTool was
 * unreachable and any query that triggered a tool came back as an empty
 * reply. These tests exercise the extracted runToolCallLoop helper against
 * a stubbed Gemini ChatSession, without requiring the Firebase Admin SDK or
 * a live Gemini API key.
 *
 * Tests cover:
 * - functionCalls() is invoked as a function and its return value is used.
 * - A tool-triggering turn runs executeTool and returns real text, not "".
 * - executeTool is exercised end to end for a tool call.
 * - The round cap throws once a misbehaving model keeps requesting tools.
 */

"use strict";

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const { runToolCallLoop } = require("../helpers/toolCallLoop");

// ---------------------------------------------------------------------------
// Stub helpers — mimic the shape of a Gemini ChatSession result without
// depending on the real SDK.
// ---------------------------------------------------------------------------

/** A turn with no tool calls — the model answered directly. */
function textOnlyResult(text) {
    return {
        response: {
            functionCalls: () => [],
            text: () => text,
        },
    };
}

/** A turn where the model asked for one or more tool calls. */
function toolCallResult(calls) {
    return {
        response: {
            functionCalls: () => calls,
            // Matches the real SDK: text() is empty on a turn where the model
            // emitted a function call instead of a reply.
            text: () => "",
        },
    };
}

describe("runToolCallLoop", () => {
    it("returns the model's text immediately when there are no tool calls", async () => {
        const initialResult = textOnlyResult("Hello, how can I help?");
        const chat = { sendMessage: async () => { throw new Error("should not be called"); } };
        const executeTool = async () => { throw new Error("should not be called"); };

        const finalText = await runToolCallLoop(chat, initialResult, executeTool);

        assert.equal(finalText, "Hello, how can I help?");
    });

    it("invokes functionCalls() as a function and runs executeTool end to end", async () => {
        const toolCalls = [];
        const initialResult = toolCallResult([
            { name: "check_system_inventory", args: {} },
        ]);
        const finalResult = textOnlyResult("You have 50 units of Paracetamol in stock.");

        const chat = {
            sendMessage: async (functionResponses) => {
                // The loop should send back one functionResponse per requested call.
                assert.equal(functionResponses.length, 1);
                assert.equal(functionResponses[0].functionResponse.name, "check_system_inventory");
                return finalResult;
            },
        };

        const executeTool = async (name, args) => {
            toolCalls.push({ name, args });
            return { status: "success", system_inventory: { "Rampur PHC": [] } };
        };

        const finalText = await runToolCallLoop(chat, initialResult, executeTool);

        // executeTool actually ran, and the final reply is real text — not empty.
        assert.equal(toolCalls.length, 1);
        assert.equal(toolCalls[0].name, "check_system_inventory");
        assert.equal(finalText, "You have 50 units of Paracetamol in stock.");
        assert.notEqual(finalText, "");
    });

    it("continues the loop across multiple tool-call rounds", async () => {
        let round = 0;
        const initialResult = toolCallResult([{ name: "report_shortage", args: { quantity: 10 } }]);

        const chat = {
            sendMessage: async () => {
                round += 1;
                if (round === 1) {
                    // Model asks for a second tool before finally answering.
                    return toolCallResult([{ name: "check_system_inventory", args: {} }]);
                }
                return textOnlyResult("Shortage reported and inventory checked.");
            },
        };

        const calledTools = [];
        const executeTool = async (name) => {
            calledTools.push(name);
            return { status: "success" };
        };

        const finalText = await runToolCallLoop(chat, initialResult, executeTool);

        assert.deepEqual(calledTools, ["report_shortage", "check_system_inventory"]);
        assert.equal(finalText, "Shortage reported and inventory checked.");
    });

    it("wraps a tool execution error and still completes the turn", async () => {
        const initialResult = toolCallResult([{ name: "report_shortage", args: {} }]);
        const finalResult = textOnlyResult("I could not report that shortage.");

        const chat = {
            sendMessage: async (functionResponses) => {
                assert.equal(functionResponses[0].functionResponse.response.error, "boom");
                return finalResult;
            },
        };

        const executeTool = async () => {
            throw new Error("boom");
        };

        const finalText = await runToolCallLoop(chat, initialResult, executeTool);

        assert.equal(finalText, "I could not report that shortage.");
    });

    it("throws once the round cap is exceeded so a misbehaving model cannot loop forever", async () => {
        const initialResult = toolCallResult([{ name: "check_system_inventory", args: {} }]);
        // Every turn keeps asking for another tool call — never resolves.
        const chat = {
            sendMessage: async () => toolCallResult([{ name: "check_system_inventory", args: {} }]),
        };
        const executeTool = async () => ({ status: "success" });

        await assert.rejects(
            () => runToolCallLoop(chat, initialResult, executeTool, 3),
            /Tool call round limit exceeded/
        );
    });
});