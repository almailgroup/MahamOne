/**
 * Hand the browser a file to save.
 *
 * Built in memory and offered through a throwaway link, so nothing is uploaded
 * anywhere to be downloaded again. The object URL is released once the click
 * has been dispatched; the browser holds its own reference until the save
 * completes.
 */
export function downloadText(
  filename: string,
  text: string,
  type = "text/csv;charset=utf-8",
): void {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}
