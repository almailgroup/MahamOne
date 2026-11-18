import type { Page } from '@playwright/test';
import { chooseOption, expect, test } from './fixtures';

/** A day of the previous calendar quarter, as the date inputs want it (yyyy-MM-dd). */
/** The status of a return not filed yet, whichever day the test runs. */
const UNFILED = /^(Ready to file|Overdue)$/;

function lastQuarter(day: number): string {
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 3, day));
  return d.toISOString().slice(0, 10);
}

/** Kuwait has no VAT: a company elsewhere turns tax on when it is set up. */
async function createUkCompany(page: Page) {
  await page.goto('./');
  await page.getByLabel('Company name').fill('Thames Print Ltd');
  await page.getByRole('button', { name: 'Other country or currency' }).click();
  await chooseOption(page, page.getByLabel('Country', { exact: true }), {
    placeholder: 'Search countries…',
    query: 'United Kingdom',
  });
  await expect(page.getByRole('switch', { name: 'This business charges tax' })).toBeChecked();
  await expect(page.getByLabel('Rate (%)')).toHaveValue('20');
  await page.getByRole('button', { name: 'Create company' }).click();
  await expect(page.getByText('Thames Print Ltd is ready.')).toBeVisible();
}

test('a VAT return is reviewed, filed, paid and undone', async ({ page }) => {
  await createUkCompany(page);

  // Last quarter: a sale of £1,000 and a purchase of £300, both with 20% VAT.
  await page.goto('#/invoices/new');
  await page.getByLabel('Bill to').click();
  await page.getByPlaceholder('Search clients…').fill('Harbour Books Ltd');
  await page.getByRole('button', { name: 'New client “Harbour Books Ltd”' }).click();
  const clientDialog = page.getByRole('dialog', { name: 'New client' });
  await clientDialog.getByRole('button', { name: 'Save client' }).click();
  await expect(clientDialog).toBeHidden();
  await page.getByLabel('Issue date').fill(lastQuarter(10));
  await page.getByLabel('Item 1 name').fill('Brochure printing');
  await page.getByLabel('Item 1 quantity').fill('1');
  await page.getByLabel('Item 1 unit price').fill('1000');
  await expect(page.getByText('£1,200.00').first()).toBeVisible();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page).toHaveURL(/#\/invoices\/[0-9a-f-]{36}$/);
  await page.getByRole('button', { name: 'More actions' }).click();
  await page.getByRole('menuitem', { name: 'Mark as sent' }).click();
  await expect(page.getByText('Sent', { exact: true }).first()).toBeVisible();

  await page.goto('#/bills/new');
  await page.getByLabel('Vendor', { exact: true }).click();
  await page.getByPlaceholder('Search vendors…').fill('Paper Mill Supplies');
  await page.getByRole('button', { name: 'New vendor “Paper Mill Supplies”' }).click();
  const vendorDialog = page.getByRole('dialog', { name: 'New vendor' });
  await vendorDialog.getByRole('button', { name: 'Save vendor' }).click();
  await expect(vendorDialog).toBeHidden();
  await page.getByLabel('Bill date').fill(lastQuarter(12));
  await page.getByLabel('Line 1 description').fill('Paper stock');
  await page.getByLabel('Line 1 rate').fill('300');
  await page.getByRole('button', { name: 'Save', exact: true }).first().click();
  await expect(page).toHaveURL(/#\/bills\/[0-9a-f-]{36}$/);

  // VAT returns are turned on, in the UK format.
  await page.goto('#/settings/accounting');
  await page.getByRole('switch', { name: 'Registered for VAT' }).click();
  await expect(page.getByLabel('Return', { exact: true })).toHaveValue('uk');
  await page.getByRole('button', { name: 'Save changes' }).click();

  await page.goto('#/vat');
  await page.getByRole('link', { name: 'Review return' }).click();
  await expect(page).toHaveURL(/#\/vat\/\d{4}-\d{2}-01$/);
  // Last quarter's return: ready to file, or overdue once its due date has passed.
  await expect(page.getByText(UNFILED)).toBeVisible();
  await expect(page.getByText('VAT due on sales and other outputs')).toBeVisible();

  // Every figure can be traced back to its documents.
  await page.getByRole('button', { name: 'Box 4 transactions' }).click();
  await expect(page.getByRole('link', { name: /^Bill BILL-/ }).first()).toBeVisible();

  await page.getByRole('button', { name: 'Mark as filed' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Reference').fill('MTD-0001');
  await dialog.getByRole('button', { name: 'Mark as filed' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('h1').locator('..').getByText('Filed', { exact: true })).toBeVisible();
  await expect(page.getByText(/ref\. MTD-0001/)).toBeVisible();
  const filedReturn = page.url();

  // £200 output VAT less £60 input VAT is paid to HMRC.
  await expect(page.getByText('£140.00').first()).toBeVisible();
  await page.getByRole('button', { name: 'Record payment' }).click();
  await dialog.getByRole('button', { name: 'Record payment' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText(/^Paid on /)).toBeVisible();

  // The closing entry is in the journals, and the books still balance.
  await page.goto('#/journals');
  await expect(page.getByText('VAT return', { exact: true }).first()).toBeVisible();
  await page.goto('#/reports/balance-sheet');
  await expect(page.getByText('Balanced', { exact: true })).toBeVisible();

  // Filing locked the period: undoing needs the lock removed first.
  await page.goto(filedReturn);
  await page.getByRole('button', { name: 'Undo filing' }).click();
  await dialog.getByRole('button', { name: 'Undo filing' }).click();
  await expect(page.getByText(/This period is locked/)).toBeVisible();

  await page.goto('#/settings/accounting');
  await page.getByRole('button', { name: 'Remove lock' }).click();
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(page.getByRole('button', { name: 'Remove lock' })).toBeHidden();
  await page.goto(filedReturn);
  await page.getByRole('button', { name: 'Undo filing' }).click();
  await dialog.getByRole('button', { name: 'Undo filing' }).click();
  await expect(page.getByText(UNFILED)).toBeVisible();
});

test('tax rates have a kind that decides where they are reported', async ({ page }) => {
  await createUkCompany(page);
  await page.goto('#/settings/taxes');
  await expect(page.getByLabel('Kind of VAT')).toHaveValue('standard');
});
