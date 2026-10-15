# Slot Filling & Clarification-Question Generation in Mainstream AI Agents

A read-only research synthesis of how mainstream frameworks detect **missing required information** and **ask clarification questions** for under-specified, multi-step tasks (e.g. "create a task" with no grade / subject / knowledge points). All claims are traced to PRIMARY sources (official API references, official framework docs, framework source). URLs are cited inline.

---

## 1. Tool / Function Calling with Required Parameters (OpenAI & Anthropic)

Both providers treat "missing info" as a **schema-validation problem**: the model is prohibited from emitting a tool call until every field listed in the schema's `required` array is present. The agent loop then inspects the returned call and prompts the user (or retries) when the model still can't produce the args.

### 1.1 OpenAI — JSON Schema `required`, strict mode, parallel calls

- A tool is defined as `{"type":"function","function":{"name","description","parameters":{<JSON Schema>},"strict":bool}}`. The `parameters` object is standard JSON Schema (Draft 7) with `properties` and a `required` array. See the official Function Calling guide: https://platform.openai.com/docs/guides/function-calling (mirror: https://developers.openai.ac.cn/api/docs/guides/function-calling).
- **`strict: true`** upgrades function calling to use the Structured Outputs engine. Under strict mode (official docs, developers.openai.ac.cn/api/docs/guides/function-calling):
  - every property in `properties` **must** appear in `required`;
  - every object must set `additionalProperties:false`;
  - optional fields are expressed as a union with `null`, e.g. `"units": {"type":["string","null"], "enum":["celsius","fahrenheit"]}`;
  - if `strict:true` but the schema violates these rules, **the request is rejected** with a descriptive error rather than silently degrading.
  - The docs explicitly recommend always enabling strict mode "to ensure function calls reliably adhere to the function schema, rather than best effort."
- **Detection of missing args / the loop.** The model returns `message.tool_calls[]`, each with `function.name` and `function.arguments` (a JSON **string** that must be `json.loads`'d). A standard production loop (OpenAI function-calling guide + community-hardened pattern) is:
  1. call the model with `tools=...`, `tool_choice="auto"`;
  2. if `msg.tool_calls` is empty → stop (the model chose to answer directly);
  3. else parse each call's `arguments`, **validate against the schema's `required` list and enums server-side**, execute, and append a `role:"tool"` message per call with `tool_call_id`;
  4. repeat until no tool calls. Cap with `MAX_TOOL_ROUNDS` to avoid infinite loops.
- **`tool_choice`** controls ask-vs-call: `"auto"` (model decides), `{"type":"function","function":{"name":...}}` (force a specific tool — used to force a structured extractor / "clarify" tool), or `"none"`. Force-to-tool + `strict` gives near-deterministic slot collection.
- **`parallel_tool_calls`**: default `true` on newer models → a single assistant turn may emit multiple `tool_calls`. The agent must execute ALL and append ALL results before the next turn (`asyncio.gather`). Set `parallel_tool_calls:false` when calls must be sequential or when one call depends on another. Each tool result is matched by `tool_call_id`, not position.

### 1.2 Anthropic — `input_schema`, `tool_use`/`tool_result`, `is_error` retry

- A tool is `{"name","description","input_schema":{<JSON Schema>}}` where `input_schema` is a JSON Schema with `type/perties/required` (https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview and the parallel-tool-use page https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use).
- **Loop & missing-args handling** (official Handle Tool Calls doc, https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls):
  - Response has `stop_reason:"tool_use"` and one or more `tool_use` content blocks, each with `id`, `name`, `input` (already-parsed dict conforming to `input_schema`).
  - You run the tool, then return a `user` message containing `tool_result` blocks keyed by `tool_use_id`.
  - **Missing-required-parameters path:** "If a tool request is invalid or missing parameters … you can continue the conversation forward with a tool_result that indicates the error, and Claude will try to use the tool again with the missing information filled in." Example payload:
    ```json
    {"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01...","content":"Error: Missing required 'location' parameter","is_error":true}]}
    ```
  - Official note: Claude **"will retry 2-3 times with corrections before apologizing"** — i.e. the clarification turn is driven by the `is_error:true` result, not by a separate prompting API.
- **Parallel tool use** (https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use): multiple `tool_use` blocks per turn are allowed by default; return all results in a single `user` message, with `tool_result` blocks **before** any text. Disable with `disable_parallel_tool_use:true` (at most one call under `auto`/`any`).
- **`tool_choice`**: `auto` (default), `any` (must call a tool), or a specific tool name (forces structured output). As with OpenAI, forcing a dedicated tool is the canonical way to guarantee slot collection.
- Note: Anthropic does not expose an OpenAI-style `strict` boolean on tools in the public docs reviewed here; schema adherence relies on `input_schema` + the `is_error`/retry loop rather than constrained decoding.

**Takeaway for slot filling:** the *schema is the contract*. Required-but-absent slots are surfaced either (a) rejected outright in strict mode, or (b) caught by the developer's server-side validation of `tool_calls`/`tool_use` and fed back as an error/reprompt, causing the model to ask the user.

---

## 2. Structured Output + Pydantic / Schema-Validated Fields (LangChain / LangGraph)

When the goal is to extract a structured record (not necessarily call an external tool), the model is pinned to a schema and **required-but-missing fields surface as validation errors that trigger a re-prompt**.

### 2.1 `model.with_structured_output(schema)` (LangChain, model level)

Official docs: https://docs.langchain.com/oss/python/langchain/models#structured-output.

- Accepts a **Pydantic model**, a **TypedDict**, or a **JSON Schema** dict.
- Required fields = fields **without a default value** in Pydantic. Optional fields use `field: T | None = None`. Example:
  ```python
  from pydantic import BaseModel, Field
  class Task(BaseModel):
      grade: str = Field(description="Target grade, e.g. Grade 9")
      subject: str = Field(description="Subject, e.g. Math")
      knowledge_points: list[str] = Field(description="List of knowledge points")
  structured = model.with_structured_output(Task)
  task = structured.invoke("Create a task")   # missing fields → validation failure
  ```
- `method` selects the backend: `"function_calling"` (forces a tool call that follows the schema), `"json_mode"` (valid JSON but schema only described in prompt), or `"json_schema"` (provider-native structured output, strongest guarantee).
- **`include_raw=True`** returns `{"raw": AIMessage, "parsed": <obj>, "parsing_error": <err|None>}`. The `parsing_error` field is the inspection point: if the model omits a required field (Pydantic raises `ValidationError`), `parsing_error` is populated and `parsed` is `None`, so the developer can catch it and re-prompt manually.
- TypedDict / JSON Schema require **manual** validation (Pydantic does it automatically). This is the key difference: Pydantic turns "missing required field" into a catchable `ValidationError`; the others leave it to you.

### 2.2 Re-prompt on `ValidationError` (Agent-level `ToolStrategy`)

Official how-to (structured output): https://python.langchain.com/docs/how_to/structured_output/.

- At the agent level, `ToolStrategy(schema=..., handle_errors=...)` wraps structured-output extraction as a tool. On validation failure:
  - a `ToolMessage` is generated containing the specific error (e.g. `1 validation error for Task.grade — Field required`);
  - the model is **automatically re-prompted** to fix it and retry.
- `handle_errors` controls behavior: `True` (default — catch all, retry with default template), `False` (raise), a `str` (custom reprompt text), an exception `type`/`tuple` (catch only those), or a `Callable[[Exception], str]` (custom handler). Relevant exception classes: `StructuredOutputValidationError`, `MultipleStructuredOutputsError`.
- This is the direct LangChain analogue of the OpenAI/Anthropic "feed the error back to the model" clarification loop, but the validation is done by Pydantic rather than by you parsing `tool_calls` by hand.

**Takeaway:** schema-driven extraction converts missing slots into `ValidationError` → auto re-prompt. Pydantic is preferred because validation is automatic and the error message is sent back verbatim.

---

## 3. Dialog State Tracking / Form-Filling Frameworks

These frameworks make slot filling **explicit and declarative** rather than LLM-judged: you enumerate required slots and the framework drives a question-per-slot loop until all are filled.

### 3.1 Rasa Forms & Slots (classic DST form-filling)

Official docs: https://rasa.com/docs/rasa/forms.

- A **form** is declared in the domain with `required_slots: [slot_a, slot_b, ...]`. Activating the form starts a loop that asks for each missing slot in order.
- **Slot mappings** (in the `slots` section) tell Rasa where to read each value from: `from_entity` (extract from a recognized entity), `from_text` (take raw text), `from_intent`, `from_trigger_intent`, `custom`. Example:
  ```yaml
  slots:
    cuisine:
      type: text
      mappings: [{type: from_entity, entity: cuisine}]
  forms:
    restaurant_form:
      required_slots: [cuisine, num_people]
  ```
- **Asking for the next slot** (`request_next_slot` behavior): the form automatically targets the first unfilled required slot and executes `utter_ask_<form>_<slot>` or `utter_ask_<slot>`; you can override with a custom action `action_ask_<form>_<slot>` / `action_ask_<slot>`. Priority: `action_ask_<form>_<slot>` > `utter_ask_<form>_<slot>` > `action_ask_<slot>` > `utter_ask_<slot>`.
- **Validation** via `FormValidationAction`: implement `validate_<slot>(slot_value, dispatcher, tracker, domain)`; returning `{slot: None}` makes the user **re-asked** for that slot. You can also define `extract_<slot>` for custom mappings and override `required_slots(...)` to **dynamically add/remove slots** based on prior answers (e.g. ask "shade or sun" only if `outdoor_seating` is true). This is the framework-native "if missing → ask" engine.
- Form auto-deactivates once all `required_slots` are filled (`$page`-style completion), then runs a submission rule.

### 3.2 Google Dialogflow CX — Form Filling (page parameters + prompts)

Official docs: https://cloud.google.com/dialogflow/cx/docs/concept/parameter.

- Each **page** can define a **form** = list of parameters to collect. For each parameter:
  - `Page.form.parameters[].required` — "Required parameters must be filled before form filling concludes, and the agent will prompt the end-user for values."
  - `...fillBehavior.initialPromptFulfillment` — the fulfillment (prompt) shown to request that parameter.
  - `...fillBehavior.repromptEventHandlers` — used when the user's answer fails; supports events `sys.no-match-1..6`, `sys.no-match-default`, `sys.no-input-1..6`, `sys.no-input-default`, and `sys.invalid-parameter` (the latter fires when a webhook **invalidates** a filled value). If no reprompt handler is defined, the initial prompt is repeated.
- The agent collects required parameters **in the order defined on the page**, prompting the user turn-by-turn ("form filling"). Optional parameters never trigger prompts; required-default-value is ignored.
- Completion is checked via session/condition references: `$page.params.status = "FINAL"` (whole form filled) and `$page.params.parameter-id.status = "UPDATED"` (a slot filled last turn). A webhook can set/invalidate parameter values via `pageInfo.formInfo.parameterInfo` in the webhook response, and `sys.invalid-parameter` reprompts.
- This is the managed-cloud equivalent of Rasa forms: declarative required slots + automatic per-slot prompts + no-match/no-input reprompt cycles.

### 3.3 Microsoft Bot Framework — WaterfallDialog + Prompt classes (now archived)

Official docs: https://learn.microsoft.com/en-us/azure/bot-service/bot-builder-prompts (note: Bot Framework SDK is archived as of 2025-12-31; Microsoft points to the **Microsoft 365 Agents SDK**).

- A **WaterfallDialog** defines an ordered list of steps; each step calls a **Prompt** class: `TextPrompt`, `NumberPrompt<T>`, `ChoicePrompt`, `ConfirmPrompt`, `AttachmentPrompt`.
- Each prompt is a two-step dialog: (1) ask via `stepContext.PromptAsync(name, new PromptOptions { Prompt = ... })`; (2) return the valid value via `stepContext.Result`, **or reprompt** if invalid.
- **Missing/invalid handling**: `PromptOptions.RetryPrompt` supplies the message shown when parsing or custom validation fails. A validator (e.g. `AgePromptValidatorAsync`) returns `bool` — `false` → the prompt reprompts automatically; `true` → value accepted. There is no LLM inference here; it is pure schema/type/range validation.
- **Adaptive Cards** (https://learn.microsoft.com/en-us/azure/bot-service/bot-builder-howto-add-media-attachments?view=azure-bot-service-4.0 and Adaptive Cards schema https://adaptivecards.io/) are the structured-input UI layer — a card with `Input.Text`, `Input.ChoiceSet`, `Input.Number`, etc., submitted as a single validated payload. This is the "form UI" counterpart to Rasa/Dialogflow slot collection.

### 3.4 LangGraph `interrupt()` / `Command(resume=)` — LLM-agent human-in-the-loop

Official docs: https://docs.langchain.com/oss/python/langgraph/interrupts (Python; JS: https://docs.langchain.com/oss/javascript/langgraph/interrupts).

- `interrupt(payload)` is called inside a graph node to **pause execution** and request external/clarifying input. The payload (any JSON-serializable value) is surfaced to the caller under `result["__interrupt__"]` (or `stream.interrupts` in streaming).
- The graph must be compiled with a **checkpointer** (`InMemorySaver` for dev; a durable one in prod) and invoked with a stable `configurable.thread_id` — that thread is the cursor for resuming.
- **Resume**: call `graph.invoke(Command(resume=<value>), config)`. The `resume` value becomes the **return value** of the `interrupt()` call inside the node. The node **restarts from its beginning** (idempotent side-effects required). Imports: `from langgraph.graph import StateGraph, START, END` and `from langgraph.types import interrupt, Command`.
  ```python
  def collect(state) -> Command[Literal["next"]]:
      answer = interrupt({"question": "Which grade and subject?", "state": state})
      return Command(goto="next", update={"slots": answer})
  graph.invoke(Command(resume={"grade":"9","subject":"Math"}), config)
  ```
- Multiple parallel interrupts are resumed with a dict: `Command(resume={"id-1": v1, "id-2": v2})`.
- This is the modern LLM-agent pattern for "stop and ask the human" — a clean superset of the older static `interrupt_before`/`interrupt_after` breakpoints, and the natural place to request missing slots before an irreversible action (see §4).

**Takeaway:** DST/form frameworks make required slots **declarative and deterministic** (ask in order, validate, reprompt). LangGraph `interrupt` brings the same "pause-for-missing-info" semantics into an LLM agent graph.

---

## 4. Plan-and-Execute / ReAct with Explicit Clarification Steps

The ReAct/agent-loop pattern (Yang et al., 2022; embodied in OpenAI tool loops and Anthropic `stop_reason=="tool_use"` loops) frames clarification as a **decision the model makes each turn**: either emit a tool call, emit text (answer/ask), or stop.

- **The loop** (identical shape across providers): call model → if it requests a tool (`tool_calls` / `tool_use`), execute and feed results back → repeat; else terminate. The decision to *ask a clarifying question* is just the model returning a **text message** instead of a tool call, or calling a dedicated `"ask_clarification"` tool whose schema captures the missing field(s).
- **Ask vs. assume a default** is **LLM-judged**, steered by:
  - `tool_choice` (`auto` lets the model skip calling when info is absent; forcing a tool forces collection);
  - the system/prompt instructions (e.g. "if grade is missing, ask; if only one subject is implied, infer it");
  - domain profile / conversation context (prior turns, user defaults).
- **Confirmation-before-action** (don't act on missing/ambiguous info):
  - **LangGraph `interrupt()`** (§3.4) is the canonical "ask a human before executing an irreversible tool" mechanism — the graph pauses, the human supplies/clarifies, then `Command(resume=)` continues.
  - **Anthropic `is_error` retry** (§1.2): if a tool was called with missing params, return `is_error:true` with the specific gap; Claude retries 2-3×, effectively asking by attempting and failing. This is confirmation-by-failure, not by explicit prompt.
  - **OpenAI `tool_choice` force + `strict`**: force a "collect_slots" tool so the model cannot answer until slots are present; or use `strict:true` so the API rejects an underspecified call.
- **Blocking vs. non-blocking**: a common production heuristic is — *ask only when a missing slot is blocking* (the next tool literally cannot run, or an action is irreversible/money-/data-affecting); *otherwise infer from context/profile and state the assumption* (e.g. "Assuming Grade 9 Math — confirm?"). This balances latency (don't interrogate for every optional detail) against risk (don't silently do the wrong thing on a critical field).
- **Plan-and-execute** variants (e.g. LangChain Plan-and-Execute, https://python.langchain.com/docs/tutorials/plan_and_execute/) add an explicit planning step where the planner can enumerate "I need X before I can do Y," surfacing missing prerequisites before execution — a more deliberate form of clarification than reactive ReAct.

---

## 5. Comparison / Tradeoffs

| Mechanism | Who detects missing info | Ask style | Determinism | Best when |
|---|---|---|---|---|
| **OpenAI/Anthropic tool `required` + strict** | Schema + your server-side validation of `tool_calls` | Model re-calls tool after `is_error`/strict reject | High with `strict` | General LLM agents, natural-language slot extraction |
| **LangChain `with_structured_output` + Pydantic** | Pydantic `ValidationError` on required fields | Auto re-prompt via `ToolStrategy.handle_errors` | High (schema-validated) | Structured record extraction, typed outputs |
| **Rasa Forms / Dialogflow CX form filling** | Framework DST loop (`required_slots` / `required`) | Per-slot `utter_ask_*` / `initialPromptFulfillment` | Very high (deterministic order) | Task-oriented dialog, few well-defined slots |
| **MS Bot Waterfall + Prompts / Adaptive Cards** | Type/range validator (`bool`) | `RetryPrompt` until valid | Very high | GUIs / card-based forms, no LLM needed |
| **LangGraph `interrupt()` / `Command(resume=)`** | Developer-inserted pause in graph | Human-in-the-loop payload via `__interrupt__` | High (explicit) | LLM agents needing human confirmation before action |
| **ReAct / plan-and-execute** | LLM-judged, prompt-steered | Model emits question or `ask_clarification` tool | Low–medium | Open-ended tasks, flexible clarification |

**When to ask vs. infer**
- **Ask** when the slot is *blocking* (tool can't run), *irreversible* (sends email, charges money, writes DB), or *high-stakes/ambiguous* with no safe default. Use schema/`required` + strict mode or a form to guarantee it.
- **Infer** when the slot is *optional*, *recoverable*, or a *strong default* exists from profile/context; state the assumption and offer correction (confirm-before-action).

**Over-prompting vs. silent wrong assumptions**
- Over-prompting (asking for every optional field) raises latency, friction, and abandonment. Mitigate with sensible defaults + explicit assumptions.
- Silent wrong assumptions (letting the model infer a critical missing slot) cause incorrect, sometimes destructive, outcomes. Mitigate with `strict`/`required`, form validation, and `interrupt()` before irreversible steps.

**Schema-driven vs. LLM-judged detection**
- *Schema-driven* (JSON Schema `required`, Pydantic, Rasa/Dialogflow required slots, prompt validators) is **deterministic, testable, and cheap** — the missing field is known before any generation. Preferred for bounded, known slot sets.
- *LLM-judged* (ReAct "should I ask?") is **flexible for novel/under-specified tasks** but non-deterministic and hard to test; it should be steered by prompts and constrained by forced tools / `strict` mode so the model can't silently skip a critical slot.
- **Hybrid (recommended):** enforce required slots via schema/form, let the LLM *infer optional ones* and *phrase the clarification question* naturally, and gate any irreversible action behind `interrupt()`/explicit confirmation.

---

## Primary Sources Cited

- OpenAI Function Calling: https://platform.openai.com/docs/guides/function-calling (mirror https://developers.openai.ac.cn/api/docs/guides/function-calling)
- OpenAI Structured Outputs: https://platform.openai.com/docs/guides/structured-outputs
- Anthropic Tool Use overview: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Anthropic Handle Tool Calls: https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls
- Anthropic Parallel Tool Use: https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use
- LangChain `with_structured_output` (models): https://docs.langchain.com/oss/python/langchain/models#structured-output
- LangChain Structured Output how-to: https://python.langchain.com/docs/how_to/structured_output/
- LangGraph Interrupts (Python): https://docs.langchain.com/oss/python/langgraph/interrupts
- LangGraph Interrupts (JS): https://docs.langchain.com/oss/javascript/langgraph/interrupts
- Rasa Forms: https://rasa.com/docs/rasa/forms
- Dialogflow CX Parameters / form filling: https://cloud.google.com/dialogflow/cx/docs/concept/parameter
- Microsoft Bot Framework prompts: https://learn.microsoft.com/en-us/azure/bot-service/bot-builder-prompts
- Microsoft 365 Agents SDK (successor): https://learn.microsoft.com/en-us/azure/bot-service/
- Adaptive Cards: https://adaptivecards.io/
- LangChain Plan-and-Execute: https://python.langchain.com/docs/tutorials/plan_and_execute/
