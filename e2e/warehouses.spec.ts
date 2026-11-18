import type { Page } from '@playwright/test';
import { chooseOption, createCompany, expect, test } from './fixtures';
import { FakeSupabase } from './cloud-fake';

/**
 * Warehouses and items issued: the owner sets up a sub-warehouse looked
 * after by an employee whose Maham One account issues items from it, and
 * sends it stock from the main warehouse. The keeper issues uniforms to a
 * security guard; nothing leaves the sub-warehouse until the owner confirms
 * it on their own device, then the stock leaves it and the guard's record
 * shows what they hold. The cloud is a stand-in that answers as the server
 * does. Made-up people and companies.
 */

let cloud: FakeSupabase;

test.beforeEach(async ({ page }) => {
  cloud = new FakeSupabase();
  await cloud.install(page);
});

const OWNER = { email: 'owner@example.com', password: 'safe-password-1', name: 'Mariam Test' };
const KEEPER = { email: 'keeper@example.com', password: 'safe-password-2', name: 'Ahmed Test' };

async function signIn(page: Page, who: typeof OWNER) {
  await page.goto('#/signin');
  await page.getByLabel('Email', { exact: true }).fill(who.email);
  await page.getByLabel('Password', { exact: true }).fill(who.password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  return page.getByRole('button', { name: `Account: ${who.name}` });
}

async function signOut(page: Page, account: ReturnType<Page['getByRole']>) {
  await account.click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  const dialog = page.getByRole('dialog', { name: 'Sign out?' });
  await dialog.getByText('Remove them from this device').click();
  await dialog.getByRole('button', { name: 'Sign out' }).click();
  await expect(page.getByRole('heading', { name: 'Welcome to Maham One' })).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Work from any device, with your team' }),
  ).toBeVisible();
}

async function addEmployee(page: Page, name: string, jobTitle: string): Promise<string> {
  await page.goto('#/employees/new');
  await page.getByLabel('Name (English)').fill(name);
  await page.getByLabel('Job title (English)').fill(jobTitle);
  await page.getByLabel('Hire date').fill('2024-03-01');
  await page.getByLabel('Basic salary').fill('300');
  await page.getByRole('button', { name: 'Save employee' }).first().click();
  await expect(page).toHaveURL(/#\/employees\/[0-9a-f-]{36}$/);
  await expect(page.getByRole('heading', { name, level: 1 })).toBeVisible();
  return page.url();
}

async function addStockItem(page: Page, name: string, cost: string) {
  await page.goto('#/products');
  await page.getByRole('button', { name: 'New item' }).first().click();
  const item = page.getByRole('dialog', { name: 'New item' });
  await item.getByRole('radio', { name: /^Stock item/ }).click();
  await item.getByLabel('Name', { exact: true }).fill(name);
  await item.getByLabel('Selling price').fill(cost);
  await item.getByLabel('Cost price').fill(cost);
  await item.getByLabel(/^Unit/).fill('pc');
  await item.getByRole('button', { name: 'Save' }).click();
  await expect(item).toBeHidden();
}

async function chooseItem(page: Page, line: number, name: string) {
  await page.getByRole('button', { name: `Item ${line}`, exact: true }).click();
  await page.getByPlaceholder('Search items…').fill(name);
  await page.getByRole('option', { name: new RegExp(name) }).click();
}

test('a keeper issues uniforms to a guard, and they leave the sub-warehouse once the owner confirms', async ({
  page,
  pageErrors,
}) => {
  test.slow();
  cloud.addUser(OWNER.email, OWNER.password, OWNER.name);
  await createCompany(page, 'Made-up Guard Services');
  await addEmployee(page, KEEPER.name, 'Warehouse supervisor');
  const guardUrl = await addEmployee(page, 'Mohammed Test', 'Security guard');
  await addStockItem(page, 'Uniform trousers', '4');
  await addStockItem(page, 'Uniform jacket', '9');

  // Opening stock in the main warehouse.
  await page.goto('#/inventory/adjustments/new?kind=opening');
  await chooseItem(page, 1, 'Uniform trousers');
  await page.getByLabel('Item 1 quantity').fill('20');
  await page.getByLabel('Item 1 unit cost').fill('4');
  await page.getByRole('button', { name: 'Add stock item' }).click();
  await chooseItem(page, 2, 'Uniform jacket');
  await page.getByLabel('Item 2 quantity').fill('10');
  await page.getByLabel('Item 2 unit cost').fill('9');
  await page.getByRole('button', { name: 'Record opening stock' }).last().click();
  await expect(page).toHaveURL(/#\/inventory\/entries\/[0-9a-f-]{36}$/);

  // Into the cloud, with the keeper's account on the team as staff.
  let account = await signIn(page, OWNER);
  await page.getByRole('button', { name: 'Keep in the cloud' }).click();
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  const companyId = [...cloud.companies.keys()][0];
  // The owner hears about the team's changes under the bell.
  await page.goto('#/settings/alerts');
  await page
    .getByRole('switch', { name: 'Tell me about changes by my team in Made-up Guard Services' })
    .click();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText('Changes by your team are on')).toBeVisible();
  const keeper = cloud.addUser(KEEPER.email, KEEPER.password, KEEPER.name);
  cloud.companies.get(companyId)!.members.set(keeper.id, 'staff');

  // A sub-warehouse of the main one, named after whoever looks after it.
  await page.goto('#/inventory?tab=warehouses');
  await page.getByRole('button', { name: 'New sub-warehouse' }).click();
  const dialog = page.getByRole('dialog', { name: 'New sub-warehouse' });
  await expect(dialog.getByLabel('Belongs to')).toHaveValue(`${companyId}-main-store`);
  await chooseOption(page, dialog.getByLabel('Looked after by'), {
    placeholder: 'Search employees…',
    query: KEEPER.name,
    option: `${KEEPER.name} EMP-001`,
  });
  await expect(dialog.getByLabel('Name', { exact: true })).toHaveValue(KEEPER.name);
  await dialog.getByLabel('Issues items from it').selectOption({ label: KEEPER.name });
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();
  const sub = page.getByRole('listitem').filter({ hasText: 'Sub-warehouse' });
  await expect(sub).toContainText(
    `${KEEPER.name}Sub-warehouseLooked after by ${KEEPER.name} (Warehouse supervisor)`,
  );

  // Stock goes to it from the main warehouse.
  await sub.getByRole('link', { name: 'Send stock' }).click();
  await expect(page.getByRole('heading', { name: 'Transfer stock' })).toBeVisible();
  await chooseItem(page, 1, 'Uniform trousers');
  await page.getByLabel('Item 1 quantity').fill('5');
  await page.getByRole('button', { name: 'Add stock item' }).click();
  await chooseItem(page, 2, 'Uniform jacket');
  await page.getByLabel('Item 2 quantity').fill('3');
  await page.getByRole('button', { name: 'Post transfer' }).click();
  await expect(page).toHaveURL(/#\/inventory\/entries\/[0-9a-f-]{36}$/);
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  const store = cloud
    .rows(companyId, 'warehouses')
    .find((r) => (r.data as { parentId?: string }).parentId);
  expect(store?.data).toMatchObject({
    name: KEEPER.name,
    parentId: `${companyId}-main-store`,
    keeper: { name: KEEPER.name, jobTitle: 'Warehouse supervisor', userId: keeper.id },
  });
  await signOut(page, account);

  // The keeper issues a pair of trousers and a jacket to the guard: it waits.
  account = await signIn(page, KEEPER);
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  await page.goto('#/inventory');
  await expect(page.getByText(`You look after ${KEEPER.name}`)).toBeVisible();
  await page.getByRole('link', { name: 'Issue items' }).first().click();
  await expect(page.getByRole('heading', { name: 'Issue items' })).toBeVisible();
  await expect(page.getByLabel('From warehouse')).toHaveValue(store!.id);
  await chooseOption(page, page.getByLabel('Issued to'), {
    placeholder: 'Search employees…',
    query: 'Mohammed',
  });
  await chooseItem(page, 1, 'Uniform trousers');
  await expect(page.getByText('5 pc left in Ahmed Test')).toBeVisible();
  await page.getByLabel('Item 1 quantity').fill('6');
  await expect(page.getByText('Only 5 left to issue.')).toBeVisible();
  await page.getByLabel('Item 1 quantity').fill('1');
  await page.getByRole('button', { name: 'Add an item' }).click();
  await chooseItem(page, 2, 'Uniform jacket');
  await page.getByLabel('Item 2 quantity').fill('1');
  await page.getByRole('button', { name: 'Send for approval' }).click();
  await expect(page.getByText(/^Sent for approval/)).toBeVisible();
  await expect(page).toHaveURL(/#\/inventory\/issues\/[0-9a-f-]{36}$/);
  await expect(
    page.getByText('Ahmed Test (Warehouse supervisor) issued to Mohammed Test (Security guard):'),
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Take back' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Confirm' })).toHaveCount(0);
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  expect(cloud.rows(companyId, 'stockIssues')).toHaveLength(0);
  const asked = cloud.rows(companyId, 'approvals')[0].data;
  expect(asked).toMatchObject({
    kind: 'stock_issue',
    status: 'pending',
    requestedBy: keeper.id,
    after: {
      warehouseId: store!.id,
      issuedBy: keeper.id,
      recipient: { name: 'Mohammed Test', jobTitle: 'Security guard' },
      lines: [
        { name: 'Uniform trousers', quantity: 1 },
        { name: 'Uniform jacket', quantity: 1 },
      ],
    },
  });
  // The keeper changes the sub-warehouse's stock only by issuing items.
  await page.goto('#/inventory/adjustments/new');
  await expect(
    page.getByLabel('Warehouse', { exact: true }).locator('option', { hasText: KEEPER.name }),
  ).toHaveCount(0);
  await signOut(page, account);

  // The owner's bell says who issued what to whom; they confirm it.
  account = await signIn(page, OWNER);
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  const bell = page.getByRole('button', { name: /^Updates/ });
  await expect(bell).toHaveAccessibleName(/^Updates: \d+ unread$/);
  await bell.click();
  const panel = page.getByRole('dialog', { name: 'Updates' });
  const update = panel.getByRole('link', {
    name: /Issued 1 Uniform trousers, 1 Uniform jacket to Mohammed Test \(Security guard\), waiting for approval/,
  });
  await expect(update).toContainText(KEEPER.name);
  await page.keyboard.press('Escape');
  await page.goto('#/approvals');
  await expect(
    page.getByText('Ahmed Test (Warehouse supervisor) issued to Mohammed Test (Security guard):'),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Confirm' }).click();
  await expect(page.getByText('Confirmed: the items are issued')).toBeVisible();
  await expect(account).toContainText('Synced', { timeout: 30_000 });
  const issues = cloud.rows(companyId, 'stockIssues');
  expect(issues).toHaveLength(1);
  expect(issues[0].data).toMatchObject({
    number: 'ISS-0001',
    status: 'posted',
    warehouseId: store!.id,
    issuedBy: keeper.id,
    recipient: { name: 'Mohammed Test' },
  });
  expect(cloud.rows(companyId, 'approvals')[0].data).toMatchObject({ status: 'applied' });

  // 4 pairs of trousers and 2 jackets are left in the sub-warehouse.
  await page.goto('#/inventory');
  await page.getByLabel('Warehouse', { exact: true }).selectOption({
    label: `Main store › ${KEEPER.name}`,
  });
  await expect(page.getByRole('row', { name: /Uniform trousers/ })).toContainText('4 pc');
  await expect(page.getByRole('row', { name: /Uniform jacket/ })).toContainText('2 pc');

  // On record: the list of items issued, and what the guard holds.
  await page.goto('#/inventory/issues');
  const row = page.getByRole('row', { name: /Mohammed Test/ });
  await expect(row).toContainText('ISS-0001');
  await expect(row).toContainText('Issued');
  await page.goto(`${guardUrl}?tab=issued`);
  await expect(page.getByText('Items held')).toBeVisible();
  const held = page.getByRole('listitem').filter({ hasText: 'Uniform trousers' });
  await expect(held).toContainText('1');
  await expect(page.getByRole('listitem').filter({ hasText: 'Uniform jacket' })).toContainText('1');
  expect(pageErrors).toEqual([]);
});
