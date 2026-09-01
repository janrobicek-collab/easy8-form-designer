import type { InitSubmissionFormData } from "./types";

/**
 * PRD M11. Keeps the requester form's fields in step with the answers given
 * so far, so a conditional section appears the moment its rule is satisfied.
 *
 * Deliberately dumb: it evaluates nothing. Which fields are asked is decided
 * by RuleEvaluator on the server, and this only notices that a rule's input
 * changed, posts every answer to
 * EasyFormDesignerSubmissionsController#refresh, and lets Turbo swap the
 * frame with whatever comes back. That is the same shape as Easy8's own
 * new-issue form (post the serialised form, replace one container), using
 * the Turbo frame the Design System already supports rather than the older
 * jQuery + `.js.erb` pathway that form still uses.
 */
export function initSubmissionForm(data: InitSubmissionFormData): void {
  whenFormReady(data.formId, (form) => watchAnswers(form, data));
}

/**
 * The real <form> does not exist yet when this module runs. `ds_form` renders
 * `<easy8-ds-form data-id="…">`, and the element carrying the id is created
 * by Vue from inside a lazily-imported custom element — so an eager lookup
 * finds nothing, and even EASY.schedule.late is no guarantee.
 *
 * Waiting for it, rather than resolving the form on each event, is what lets
 * the baseline snapshot below be taken from what the server actually
 * rendered. Without a correct baseline the first answer would be compared
 * against nothing and silently swallowed.
 */
function whenFormReady(formId: string, ready: (form: HTMLFormElement) => void): void {
  const existing = document.getElementById(formId);
  if (existing instanceof HTMLFormElement) {
    ready(existing);
    return;
  }

  const observer = new MutationObserver(() => {
    const form = document.getElementById(formId);
    if (!(form instanceof HTMLFormElement)) return;

    observer.disconnect();
    ready(form);
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

function watchAnswers(form: HTMLFormElement, data: InitSubmissionFormData): void {
  // A multi-value widget (multi-select, file upload) submits under
  // `answers[token][]`, everything else under `answers[token]`. Both spellings
  // are watched so a multi-select can drive a rule — which it now can, since
  // the operator rework: a multi-value list is an ordinary :list_optional.
  const names = new Set(data.triggerTokens.flatMap((token) => [`answers[${token}]`, `answers[${token}][]`]));

  let snapshot = triggerSnapshot(form, names);
  let focusName: string | null = null;

  // Compares the answers rather than reacting to whatever element the event
  // came from. That is what makes a Design System control usable as a rule
  // input at all: DSDatepicker's value lives in a hidden input written by
  // Vue, and the visible text box it sits behind carries no name of its own.
  //
  // Idempotent by construction, so it is safe to call from several signals.
  const check = (): void => {
    const next = triggerSnapshot(form, names);
    if (next === snapshot) return;

    snapshot = next;
    focusName = elementName(document.activeElement);
    submitRefresh(form, data.refreshFormId);
  };

  // Native `change` covers everything the requester edits directly — typing,
  // and the plain select/radio/checkbox widgets this form deliberately uses.
  form.addEventListener("change", check);

  // …but a value Vue assigns fires NO native event, so picking a date from
  // the calendar (or a name from the autocomplete) would otherwise go
  // unnoticed. Both commit on a click, and the calendar is teleported out of
  // the form, so the click is watched on the document; the check is deferred
  // by a macrotask so Vue has flushed its DOM update by the time it runs.
  //
  // A blur can commit a typed date the same way, for the same reason.
  document.addEventListener("click", () => defer(check));
  form.addEventListener("focusout", () => defer(check));

  document.addEventListener("turbo:before-frame-render", (event) => {
    if (isFrame(event, data.frameId)) preserveFileInputs(event);
  });

  document.addEventListener("turbo:frame-load", (event) => {
    if (!isFrame(event, data.frameId)) return;

    snapshot = triggerSnapshot(form, names);
    restoreFocus(form, focusName);
    focusName = null;
  });
}

/**
 * The answers a rule reads, as a comparable string. Files are ignored: a rule
 * cannot be driven by an upload (FormField#filter_type is nil for one), and a
 * File has no useful string form.
 */
function triggerSnapshot(form: HTMLFormElement, names: Set<string>): string {
  const parts: string[] = [];

  new FormData(form).forEach((value, name) => {
    if (names.has(name) && typeof value === "string") parts.push(`${name}=${value}`);
  });

  return parts.join("&");
}

/**
 * Copies the current answers into the hidden sibling form and submits it.
 *
 * Every answer travels, not just the rule's input, because the response
 * re-renders every field — an answer left behind would come back as an empty
 * input. This is exactly how Easy8's issue form preserves what you have typed
 * across a reload: the params round trip IS the preservation, there is no
 * client-side copy-back.
 */
function submitRefresh(form: HTMLFormElement, refreshFormId: string): void {
  const refreshForm = document.getElementById(refreshFormId);
  if (!(refreshForm instanceof HTMLFormElement)) return;

  refreshForm.querySelectorAll("[data-efd-answer]").forEach((stale) => stale.remove());

  new FormData(form).forEach((value, name) => {
    // Files cannot be carried across, and the refresh has no use for them.
    // The main form's token is skipped too — the hidden form has its own.
    if (typeof value !== "string" || name === "authenticity_token" || name === "utf8") return;

    refreshForm.appendChild(answerInput(name, value));
  });

  refreshForm.requestSubmit();
}

function answerInput(name: string, value: string): HTMLInputElement {
  const input = document.createElement("input");
  input.type = "hidden";
  input.name = name;
  input.value = value;
  input.setAttribute("data-efd-answer", "");

  return input;
}

/**
 * Moves the live file inputs into the incoming frame instead of letting Turbo
 * replace them with empty ones. A FileList cannot be re-rendered — browsers
 * refuse to populate a file input — so the element itself has to survive.
 *
 * Safe only because these are plain <input type="file"> tags: a Design System
 * custom element must never be re-inserted, since its prop <script> children
 * are consumed and removed when it first mounts.
 */
function preserveFileInputs(event: Event): void {
  const frame = event.target as HTMLElement;
  const incoming = (event as CustomEvent<{ newFrame?: HTMLElement }>).detail?.newFrame;
  if (!incoming) return;

  frame.querySelectorAll<HTMLInputElement>('input[type="file"]').forEach((live) => {
    if (!live.files?.length || !live.name) return;

    incoming.querySelector<HTMLInputElement>(`input[type="file"][name="${CSS.escape(live.name)}"]`)?.replaceWith(live);
  });
}

/**
 * Puts focus back where it was, but only when the swap actually took it away.
 * A control Turbo left alone keeps its own focus and must not be disturbed.
 */
function restoreFocus(form: HTMLFormElement, name: string | null): void {
  if (!name) return;
  if (document.activeElement !== document.body) return;

  form.querySelector<HTMLElement>(`[name="${CSS.escape(name)}"]`)?.focus();
}

function isFrame(event: Event, frameId: string): boolean {
  return event.target instanceof HTMLElement && event.target.id === frameId;
}

function elementName(target: EventTarget | null): string | null {
  return target instanceof HTMLElement ? target.getAttribute("name") : null;
}

/** A macrotask, so Vue's own microtask DOM flush has already happened. */
function defer(fn: () => void): void {
  window.setTimeout(fn, 0);
}
