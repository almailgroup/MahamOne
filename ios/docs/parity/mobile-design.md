# Maham One on a phone: the shell and the design system

This is how the web app looks below **1024px** (Tailwind `lg`), which is everything an iPhone
shows. 768px (`md`) is only where tables turn into lists. On a phone the touch variants
(`pointer-coarse:`) apply too, so controls are at least 44pt tall. 1rem = 16pt; spacing comes
in 4pt steps.

Icons are lucide-react 1.50.0: 16pt in buttons, 20pt in the tab bar, 18pt in menu rows.

Colours are OKLCH. Safari draws the saturated ones in Display P3, so the native themes use
**P3 values**. The Swift colours are generated from `src/lib/themes.ts` by
`scripts/ios-themes.ts`; never hand-copy them.

## The frame (`src/app/layout.tsx`)

- **Page:** `bg-page`, and the window scrolls. Padding is 16pt at the sides, 20pt at the top,
  and 96pt plus the bottom safe area at the bottom.
- **Changing page** scrolls back to the top.
- **Lazy pages** show a spinner with "Loading…".

### Top bar (`src/features/shell/header.tsx`)

The bar is sticky and 56pt tall, with 12pt side padding and 8pt gaps. It is `surface` at
85% with a 12pt blur and no border. After 2pt of scroll it takes the shadow
`0 10 24 −18 rgb(15 23 42/.35)`.

Its contents, from the start side:

1. **Menu** (ghost, 44pt): opens the drawer.
2. **Maham One mark:** 32pt, a link to `/`. Hidden below 360pt.
3. **Divider:** 1×20pt, slate-200. Hidden below 360pt.
4. **Company name:** 14pt, weight 600, slate-900, truncated. Not tappable.
5. A flexible spacer.
6. **Search:** full-screen search.
7. **Language switch:** 32pt tall, 10pt side padding, 8pt radius, 14pt weight 500,
   slate-600. Shows the `Languages` icon and the other language's name ("العربية" /
   "English").
8. **Updates bell:** only for cloud owners and approvers who turned on "Changes by your
   team".
   - The badge is red-solid, 16pt tall, with 10pt weight-600 white text and a maximum of
     "99+".
   - It opens a popover 24rem wide with a 16pt radius.
9. **App switcher:** `LayoutGrid`.

### Floating tab bar (`src/features/shell/bottom-bar.tsx`)

**Position:** fixed, 12pt from the sides and `max(12, safe area)` from the bottom. 16pt
radius.

**Look:** `surface` at 95%, 12pt blur, a ring of slate-900 at 5%, and the shadow
`0 10 30 −8 rgb(15 23 42/.3)`.

**Layout:** 5 columns, 64pt tall, 6pt side padding, at most 512pt wide.

**Tabs:** icon and label stacked with a 4pt gap. Labels are 12pt weight 500. Active is
primary-700; idle is slate-600.

**Centre button:**
- 48×48pt, 16pt radius, `primary-solid` (pressed: `-active`), with a 24pt `Plus` in
  `on-primary`.
- Shadow: `shadow-lg` tinted `primary-solid` at 30%.
- It opens the **Create** sheet. People who can only view get a slate-100 square with a
  20pt `Search` icon that opens search instead.

**Slot 5, "More":** opens the drawer, and is never shown as active.

**Hiding:** the bar hides while the keyboard is up, and on editor pages, which show a
`StickyActions` bar in the same shell with 10pt padding and the buttons at the end.

**Order** follows the reading direction (in Arabic, Home is on the right).

**Tabs per app** (from each app's `manifest.ts`):

| App | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|
| Books (classic) | Home `House` | Invoices `FileText` | Expenses `Wallet` |
| Books (split) | Home | Bills `Receipt` | Expenses |
| People | Home | Employees `IdCard` | Payroll `WalletCards` |
| CRM | Home | Pipeline `KanbanSquare` | Quotes `ScrollText` |
| Compliance | Home | Calendar `CalendarClock` | Documents `FolderCheck` |
| Sales | Home | Invoices | Quotes |
| Inventory | Home | Stock `Warehouse` | Products `Package` |

**The current app** is the one that owns the URL. On suite pages, it is the last app used
(`almailbooks.suite.app`, default Books).

**App order:**
- Classic layout: Books, People, CRM, Compliance.
- Split layout: Sales, Books, Inventory, People, CRM, Compliance.

### Create sheet (the + button)

**The sheet:**
- Slides up over 220ms.
- 24pt top corners, at most 88% of the screen tall, `surface`.
- Backdrop: `overlay` at 40%.
- Title row: "Create new", 16pt weight 600, with a 44pt round close button.

**Groups:**
- Heading: 12pt, weight 600, slate-500.
- Tiles: a 3-column grid with 6pt gaps. Each tile is at least 80pt tall with a 12pt radius
  and a 12pt weight-500 slate-700 label. Its icon is 20pt primary-700 in a 40pt primary-50
  circle.

**Order:** the current app's groups first, then the other apps'. Books in the classic
layout has:

- **Sales:** Invoice, Quote, Proforma invoice, Sales order, Delivery note, Credit note,
  Recurring invoice, Payment received.
- **Purchases:** Bill, Expense, Purchase order, Payment made, Vendor credit.
- **Contacts and items:** Client, Vendor, Product or service.
- **Accounting:** Manual journal, Fixed asset, Stock adjustment, Items to an employee.
- **People:** Employee, Employee letter, Manpower costing (when costing is available).

The icons are in `src/features/shell/create.ts`.

### Drawer ("More" or Menu)

**The panel:**
- Slides in from the start edge over 200ms (`cubic-bezier(.16,1,.3,1)`).
- `min(320, 100vw − 48)` wide, `bg-shell`, 24pt radius on the end corners, `shadow-2xl`.
- Backdrop: `overlay` at 40%.
- Header: "Menu" (14pt, weight 600, slate-600), the theme button and close.

**From the top:**

1. **Logo:** 32pt tall, with a `-dark` version for dark themes.
2. **Company switcher card:**
   - `surface`, 16pt radius, 8pt padding, ring, at least 48pt tall.
   - The company's 32pt logo, or its initials on `primary-solid`.
   - The name, then "Company type · KWD" (12pt slate-500), and `ChevronsUpDown`.
   - Its menu lists the companies (with a check on the current one) and "Add company".
3. **App tiles:**
   - 4 columns, or 3 when there are more than 4 apps; 4pt gaps.
   - 12pt radius, at least 48pt tall, 11pt weight-500 labels.
   - The current app gets `surface`, `shadow-xs` and a ring.
4. **Current app row:** its mark and name (14pt, weight 600), with "Beta" on CRM.
5. **Navigation list:**
   - Items are 44pt, 12pt radius, 12pt side padding, 14pt weight 500, with 18pt icons.
   - Idle: slate-700 text and slate-500 icon.
   - Active: `surface`, primary-700 text, primary-600 icon, `shadow-xs`, ring.
   - Groups fold with a `ChevronDown`. Their children are indented 42pt.
   - Sales and Integrations start open. Groups remember being open or closed.
6. **Company links and integrations.**
7. **Footer:** Templates and Settings for Books and Sales; Settings only for the other apps.
8. **Account card:**
   - An avatar 36pt round in primary-100, with primary-800 initials.
   - The name and the sync status.
   - Its menu: Sync now, Cloud and sync, Team, Account settings, Sign out.

**Navigation per app** (`src/apps/*/manifest.ts`):

- **Books:**
  - Home; Dashboard.
  - **Sales:** Clients, Quotes, Proforma invoices, Sales orders, Invoices, Delivery notes,
    Payments received, Credit notes, Recurring invoices.
  - **Purchases:** Vendors, Purchase orders, Bills, Expenses, Payments made, Vendor credits.
  - Cheques.
  - **Inventory:** Products & services, Stock and warehouses, Issued items.
  - Banking.
  - **Accounting:** Chart of accounts, Manual journals, Fixed assets, Year-end close, VAT
    returns (when taxes are on).
  - Reports; Approvals (when approvals are on).
- **People:** Home, Overview, Directory, Employees, Payroll, Leave, Leave reasons, Staff
  loans, Letters, Manpower costing, Payroll settings, Approvals.
- **CRM:** Home, Pipeline, Prospects, Customers, Quotes, Sales orders.
- **Compliance:** Home, Calendar, Documents, Vehicles, Files.

### App switcher (`src/suite/switcher.tsx`)

**The dropdown:** 23rem wide, 16pt radius, `shadow-xl`, a 4-column grid (3 when there are
more than 4 apps).

**Items:**
- 12pt radius.
- The app mark is 40pt with a 12pt radius and a 20pt icon; the name is 12pt weight 600.
- The current app gets slate-50, a ring and a primary-600 check.

**Footer:** "Maham One home".

**App colours** (fixed, not themed):

| App | Icon | Background / icon colour |
|---|---|---|
| Books | `BookOpenText` | indigo-100 / indigo-700 |
| People | `UsersRound` | emerald-100 / emerald-700 |
| CRM | `Handshake` | sky-100 / sky-700 |
| Compliance | `ShieldCheck` | amber-100 / amber-800 |
| Sales | `ShoppingBag` | violet-100 / violet-700 |
| Inventory | `Boxes` | teal-100 / teal-800 |

**Maham Tasks:** the web Maham One has **no Maham Tasks switcher**. In the native app,
Maham Tasks is the second department.

### Search (full screen)

- **Input row:** 56pt tall, slate-200 bottom border, a 20pt slate-400 `Search` icon,
  16pt input text.
  - Placeholder: "Search clients, documents, items or pages…".
  - A "Cancel" button in primary-700.
- **Section labels:** 12pt, weight 600, slate-500.
- **Rows:** at least 44pt tall, 8pt radius.
  - The icon sits in a 32pt slate-100 tile.
  - Title 14pt weight 500; subtitle 12pt slate-500; amounts in tabular figures.
  - The highlighted row turns primary-50.

## Design tokens

### Themes

There are 20 themes, generated from recipes in `src/lib/themes.ts`:

- **Light:** Classic, Gulf blue, Sky, Turquoise, Oasis, Desert sand, Sunset, Rose,
  Lavender, Graphite.
- **Dark:** Midnight, Deep sea, Lagoon, Oasis night, Desert night, Ember, Rose night,
  Amethyst, Charcoal, Black.

The names are in `src/features/theme/names.ts`.

**What each theme defines:**
- 11-step ramps for primary, slate (the only grey), red, amber, emerald, blue, violet,
  indigo, sky and teal.
- Roles: `surface`, `page`, `shell`, `overlay`, `primary-solid` (with hover and active),
  `on-primary`, `red-solid`, chart and aging colours.
- Dark themes flip the ramps, so "slate-900 = main text" holds in every theme.

**Saving the choice:** `almailbooks.theme` holds
`{mode: light|dark|system, light: id, dark: id}`. The defaults are light mode, Classic and
Midnight.

### Roles

| Role | Token |
|---|---|
| Page background | `page` (slate-50) |
| Main text | slate-900 |
| Cards, inputs, menus | `surface` |
| Drawer | `shell` |
| Primary fills | `primary-solid`, with text in `on-primary` |
| Links | primary-700 |
| Accent icons | primary-600 |
| Tints | primary-50 / primary-100 |
| Muted | slate-100 fill, slate-500 text |
| Borders | slate-200 cards, slate-300 inputs, slate-100 dividers |
| Destructive | `red-solid`; text red-600 / red-700; tint red-50 |
| Focus | 2pt primary-500, offset 2pt; inputs get a 3pt primary-500 ring at 15% |
| Hairline rings | slate-900 at 5% |

### Shape, shadow and motion

**Radius:**

| Size | Used for |
|---|---|
| 6 | — |
| 8 | buttons, inputs |
| 12 | cards, dialogs |
| 16 | tab bar, menus, tiles |
| 24 | drawer, sheet |

**Shadows:**

| Name | Value |
|---|---|
| xs | `0 1 2 rgb(0 0 0/.05)` |
| sm | `0 1 3 rgb(0 0 0/.1), 0 1 2 −1 rgb(0 0 0/.1)` |
| lg | `0 10 15 −3 /.1, 0 4 6 −4 /.1` |
| xl | `0 20 25 −5 /.1, 0 8 10 −6 /.1` |
| 2xl | `0 25 50 −12 rgb(0 0 0/.25)` |

**Motion** (all `cubic-bezier(.16,1,.3,1)` unless noted):

| Animation | Duration |
|---|---|
| Fade | 150ms |
| Pop-in | 160ms |
| Drawer | 200ms |
| Sheet | 220ms |
| Other transitions | 150ms, `cubic-bezier(.4,0,.2,1)` |

### Type

**Fonts:** Inter Variable with the OpenType features `cv11` and `ss01`, plus IBM Plex Sans
Arabic (400, 500, 600, 700) for Arabic.

| Use | Size / line height, weight, colour |
|---|---|
| Page title | 24/32, 600, −0.025em, slate-900 |
| Card, dialog and sheet titles | 16/24, 600 |
| Home section titles | 14/20, 600, slate-500 |
| Body and table text | 14/20 |
| Phone list-row title | 16, 500 |
| Meta | 12/16, slate-500 |
| Table header | 12, 500, uppercase, +0.025em, slate-500 |
| Badges, tab labels | 12, 500 |

Amounts use tabular figures. In Arabic, letter-spacing is normal.

## Components

### Button (`src/components/ui/button.tsx`)

**Shared:** 8pt radius, weight 500, 8pt gap, 16pt icons, disabled at 50%.

**Sizes:**

| Size | Height | Text |
|---|---|---|
| xs | 28 | 12 |
| sm | 32 | 14 |
| md | 36 | 14 |
| lg | 44 | 16 |

On a phone every button is at least 44pt tall.

**Variants:**

| Variant | Look |
|---|---|
| primary | `primary-solid`, `on-primary`, `shadow-sm` |
| secondary | slate-900 fill, `surface` text |
| outline | slate-300 border, `surface`, slate-700, `shadow-xs` |
| ghost | slate-600, slate-100 when pressed |
| danger | `red-solid`, white text |
| subtle | primary-50, primary-700 |

When loading, a spinning `Loader2` sits before the label.

### Page header

- Title, then a description (14pt slate-500).
- Actions wrap below with 8pt gaps.
- 16pt between the title and the actions; 24pt below the header.

### Card

- `surface`, 12pt radius, slate-200 border, `shadow-xs`.
- Header: 20×16pt padding with a slate-100 border below.
- Body: 20pt padding.

### Inputs (`src/components/ui/form.tsx`)

**Field:** 8pt radius, slate-300 border, `surface`, 12pt side padding, `shadow-xs`. On a
phone it is 44pt tall with 16pt text.

**States:**
- Placeholder: slate-400.
- Focused: primary-500 border plus a 3pt ring at 15%.
- Invalid: red-400.
- Disabled: slate-50 with slate-500 text.

**Labels and messages:**
- Label: 14pt, weight 500, slate-700, 6pt above the field.
- Hint: 12pt slate-500. Error: 12pt red-600.

**Controls:**
- Select: native, with a `ChevronDown`.
- Switch: a 24×44pt track (`primary-solid` on, slate-300 off) with a 20pt white knob.
- Amount fields: left to right, aligned to the end, accepting Arabic-Indic digits.
- Searchable select (`src/components/ui/combobox.tsx`): a popover with search and an
  optional "Create …" row.

### Date field (`src/components/ui/date-field.tsx`)

- A text field in the company's date format, with a `CalendarDays` button.
- The calendar is 19rem wide, starts on Sunday, and shows 6 rows of 36pt days.
- Selected: `primary-solid`. Today: primary-700 with a primary-300 ring. Friday and
  Saturday: slate-500.
- Quick picks: Today, In 7 days, In 30 days, End of month.

### Lists on a phone (`src/apps/books/pages/documents/list.tsx`)

- Rows are divided by slate-100 lines, with 16×12pt padding.
- **Start side:** the client name (16pt, weight 500), then "number · date" (12pt
  slate-500).
- **End side:** the amount (14pt, weight 600, tabular), then the badges.
- **Above:** a segmented filter and a search field.
- **Below:** a totals line, then "Show more".
- The generic version is `ListCard`, with rows at least 56pt tall.

### Badges

Fully rounded, 8×2pt padding, 12pt weight 500, 1pt inner ring.

| Tone | Background | Text | Ring |
|---|---|---|---|
| gray | slate-100 | slate-700 | slate-500 at 10% |
| slate | slate-200 | slate-700 | slate-500 at 20% |
| blue | blue-50 | blue-700 | blue-600 at 15% |
| amber | amber-50 | amber-800 | amber-600 at 20% |
| green | emerald-50 | emerald-700 | emerald-600 at 20% |
| red | red-50 | red-700 | red-600 at 15% |
| violet | violet-50 | violet-700 | violet-600 at 15% |

**Status to tone** (`src/lib/status.ts`):

| Tone | Statuses |
|---|---|
| gray | draft, not delivered |
| blue | sent, open, confirmed, issued, cheque in hand |
| amber | partially paid, expired, partially invoiced, partially billed, partially delivered, security cheque held |
| green | paid, accepted, applied, delivered, cleared, cashed |
| red | overdue, declined, returned |
| violet | invoiced, converted, billed, deposited |
| slate | void, cancelled, given back |

### Empty state

- Centred, 24×56pt padding.
- A 48pt primary-50 circle with a 24pt primary-600 icon.
- Title 16pt weight 600; description 14pt slate-500, at most 384pt wide.

### Dialogs (`src/components/ui/overlay.tsx`)

Dialogs are **centred**, not bottom sheets:

- Size: the screen width minus 32pt.
- Look: 12pt radius, `shadow-xl`, pops in (scale .97 → 1).
- Header: 20×16pt padding with a border, and a close button.
- Footer: sticky, slate-50, with the buttons stacked full width and the primary one on top.

The only bottom sheet is Create.

### Menus

Dropdowns are anchored popovers:

- The panel: `surface`, 8pt radius, slate-200 border, 4pt padding, `shadow-lg`, at least
  192pt wide.
- Items: at least 44pt tall, 14pt slate-700.
- Danger items: red-600 on red-50.

### Toasts

Sonner, at the bottom, 92pt plus the safe area up, with a close button.

### Tabs

- **Segmented control:**
  - A slate-100 track with an 8pt radius and 4pt padding.
  - Segments have a 6pt radius and are at least 40pt tall, with 14pt weight-500 labels.
  - The selected segment is `surface`, slate-900, `shadow-sm`.
  - It scrolls sideways.
- **Underline tabs:** primary-600 underline, primary-700 text.

### Other components

- **Loading:** no skeletons; a spinner (16pt `Loader2` with 14pt slate-500 text).
- **"Ask AI":** a 48pt pill with `Sparkles`, floating above the tab bar at the end side.
  On a phone it shows the icon only.
- **View-only banner:** amber-50, amber-900 text, an `Eye` icon.

## Language

**English** is the key: `t('…')`, `tp(n, one, other)`.

**Arabic** lives in 63 files, `src/i18n/ar/*.ts`, with about 6,350 entries:
- Plurals are `{zero, one, two, few, many, other}`.
- Missing entries show in English.
- The language is saved as `almailbooks.language`.

**Right to left:**
- Arabic sets `dir="rtl"`, and layouts use start and end throughout.
- Mirrored icons: arrows and chevrons left/right, `ArrowUpRight`, `ArrowDownLeft`, `Undo2`,
  `Redo2`, `CornerDownRight`, `LogIn`, `LogOut`, `Send`, `ListIndentIncrease`.

**Formatting** (`src/lib/format.ts`):
- Locale: Arabic uses `ar-KW-u-nu-latn` (Western digits); English uses the company's
  locale (default `en-KW`).
- Money: "KD 1,234.500" in English, "1,234.500 د.ك" in Arabic. Foreign currencies show
  their code.
- Dates: `dd/MM/yyyy`.
- Quantities: up to 6 decimals. Percent: up to 4.

## Home (`/`, `src/suite/home/index.tsx`)

Sections are 20pt apart. From the top:

1. **Greeting:** "Good morning", "Good afternoon" or "Good evening" (before 12:00, before
   18:00, after), 24pt weight 600. Below it, "Company · date".
2. **Launcher** (`src/suite/home/launcher.tsx`):
   - A find box: 44pt tall, rounded, "Find an app or tool…".
   - **Your apps:** 4 columns.
     - Each app is a 64pt circle in its colours with a 28pt icon, its name, and a status
       line ("3 overdue invoices", "12 employees", "All up to date").
     - Pills: "Beta" or "View only".
   - **Create:** up to 6 tiles from Invoice, Quote, Expense, Payment received, Bill, Client
     and Employee.
     - Each is a 56pt primary-100 circle with a primary-700 icon.
     - A 20pt `primary-solid` plus badge.
   - **Tools:** a card per app.
   - **Company tools; Integrations.**
3. **Needs attention:**
   - Topic chips.
   - Up to 8 rows (icon red-600 or amber-600, a title, a status line, the amount or an
     arrow), then "And N more."
   - With nothing due: "Nothing needs attention right now."
4. **Approval requests**, when some are waiting.
5. **At a glance:** Owed to you, Bills to pay, Cheques in hand.
