/** Minimal class merge without pulling UI library for className glue. */
export function cx(...parts: Array<string | undefined | false>): string {
  return parts.filter(Boolean).join(" ");
}
