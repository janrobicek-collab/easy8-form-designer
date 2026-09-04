import { tokenPlaceholder } from "../types";

// Pure string/regex helpers for the subject/description templates — kept
// free of the store's reactive state so formBuilderStore.ts stays under
// eslint's max-lines ceiling and each of these stays independently testable.

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Every "{{ token }}" occurrence, tolerant of the same whitespace padding
// TemplateCompiler accepts server-side. The brace delimiters bound the match
// exactly, so a token that happens to be a substring of another can't match
// by accident.
function tokenPattern(token: string): RegExp {
  return new RegExp(`\\{\\{\\s*${escapeRegExp(token)}\\s*\\}\\}`, "g");
}

function sectionBlockPattern(token: string): RegExp {
  return new RegExp(
    `\\{\\{#\\s*${escapeRegExp(token)}\\s*\\}\\}([\\s\\S]*?)\\{\\{/\\s*${escapeRegExp(token)}\\s*\\}\\}`,
    "g"
  );
}

/** `excludeToken` lets a field's own current token be re-derived on rename without colliding with itself. */
export function tokenFor(existingTokens: string[], label: string, excludeToken: string | null = null): string {
  const base = label.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "field";
  let candidate = base;
  let n = 1;
  while (existingTokens.some((t) => t === candidate && t !== excludeToken)) {
    n += 1;
    candidate = `${base}_${n}`;
  }
  return candidate;
}

export function sectionTokenFor(existingTokens: string[], name: string, excludeToken: string | null = null): string {
  const base = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "section";
  let candidate = base;
  let n = 1;
  while (existingTokens.some((t) => t === candidate && t !== excludeToken)) {
    n += 1;
    candidate = `${base}_${n}`;
  }
  return candidate;
}

// TemplateCompiler raises UnknownToken for any template referencing a field
// that no longer exists, so a deleted field's dangling "{{ token }}" doesn't
// just look stale, it breaks every future submission until someone notices.
// Surrounding literal text is left as-is — only the placeholder is removed,
// matching the rename behavior.
export function renameTokenInTemplate(template: string, oldToken: string, newToken: string): string {
  return template.replace(tokenPattern(oldToken), tokenPlaceholder(newToken));
}

export function removeTokenFromTemplate(template: string, token: string): string {
  return template.replace(tokenPattern(token), "");
}

export function renameSectionTokenInTemplate(template: string, oldToken: string, newToken: string): string {
  return template.replace(
    sectionBlockPattern(oldToken),
    (_match, inner: string) => `{{#${newToken}}}${inner}{{/${newToken}}}`
  );
}

// Removes the markers but KEEPS the block's text — the section is gone, so
// its content is now unconditional rather than something to silently delete
// along with whatever the author wrote around it.
export function removeSectionTokenFromTemplate(template: string, token: string): string {
  return template.replace(sectionBlockPattern(token), (_match, inner: string) => inner);
}

// Appends a field's token to a template if it isn't already referenced there
// — prefills Subject/Description when a field is mapped straight to one of
// them, so the author doesn't have to hand-type the token.
export function withTokenPrefilled(template: string, token: string): string {
  const placeholder = tokenPlaceholder(token);
  if (template.includes(placeholder)) return template;

  return template.length ? `${template} ${placeholder}` : placeholder;
}
