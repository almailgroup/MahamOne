import { msg, type Language } from '@/i18n';
import type { MemberRole } from '@/cloud/roles';
import { activeLink, navLinks, type NavEntry, type NavLink } from '@/features/shell/nav';
import type { AppId, SuiteApp } from '@/suite/types';

/**
 * What the AI assistant is told with each question (Gemini's system
 * instruction): who it is and how it answers, where the person is in the
 * app, and a short guide to Maham One built from the apps' manifests (the
 * sidebars the person sees) with a line written here for each app.
 *
 * Never records: no names, numbers, amounts or form values, and the page's
 * address without its query and with record ids replaced by ":id". In this
 * first version the assistant knows only what the person types. Kept
 * under 3 KB.
 */

export interface AiPlace {
  /** The app whose sidebar is open ("Maham People"). */
  app: string;
  /** The page, as the sidebar names it in the interface language ("Employees"). */
  page: string;
  /** The page's address, without query, ids as ":id" ("/employees/:id"). */
  path: string;
  language: Language;
  /** Null: not known (a company kept on this device has no roles). */
  role: MemberRole | null;
}

/** An app of the guide: its name and its sidebar, as the person sees them. */
export interface GuideApp {
  app: SuiteApp;
  nav: NavEntry[];
}

/**
 * A line about each app, beyond its sidebar. English, as the whole
 * instruction (the model answers in the person's language), and plain ASCII
 * where it can be: the instruction is counted in bytes.
 */
const ABOUT: Record<AppId, string> = {
  books:
    'accounting: sales and purchase documents (a quote becomes an invoice in one click), payments, post-dated cheques, banking, ledger, reports; statements of account on a customer page',
  sales: 'quotes, proformas, sales orders, invoices, delivery notes, payments received',
  inventory:
    'items with codes and labels, stock per warehouse, uniforms issued, counts, landed costs',
  people:
    'HR: employees and their papers, payroll with PIFSS, leave, staff loans, letters; end-of-service settlement on an employee page',
  crm: 'follow-up of quotes in a pipeline, prospects',
  compliance: 'licences, staff papers and statutory deadlines, with reminders before expiry',
};

/** Maham Books of the split layout: the finance app. */
const ABOUT_FINANCE =
  'finance: purchases, cheques, banking, ledger, reports; invoices and payments under Receivables';

const ROLE_NAMES: Record<MemberRole, string> = {
  owner: 'owner',
  admin: 'admin',
  accountant: 'accountant',
  staff: 'staff',
  viewer: 'viewer (looks, changes nothing)',
};

/** Pages of the suite that no sidebar lists. */
const SUITE_PAGES: { to: string; label: string }[] = [
  { to: '/files', label: msg('Files') },
  { to: '/approvals', label: msg('Approval requests') },
  { to: '/notifications', label: msg('Updates') },
  { to: '/setup', label: msg('Add company') },
];

/** A path segment that is a word ("employees", "leave-reasons"), not an id or a date. */
const WORD = /^[a-z]+(?:-[a-z]+)*$/;

/** The page's address for the assistant: no query or hash, record ids as ":id". */
export function placePath(pathname: string): string {
  const path = pathname.split(/[?#]/)[0] || '/';
  const safe = path
    .split('/')
    .map((segment) => (segment === '' || WORD.test(segment) ? segment : ':id'))
    .join('/');
  return safe.startsWith('/') ? safe : `/${safe}`;
}

/**
 * The page's name (an English key): the sidebar link it is under, in the
 * open app or another one, a page of the suite, or Settings with its
 * section ("Settings › Team").
 */
export function pageLabel(
  pathname: string,
  current: GuideApp,
  others: readonly SuiteApp[],
  settings: readonly { path: string; label: string }[],
  translate: (key: string) => string,
): string {
  const path = pathname.split(/[?#]/)[0] || '/';
  if (path === '/settings' || path.startsWith('/settings/')) {
    const section = settings.find((s) => path === `/settings/${s.path}`);
    return section
      ? `${translate(msg('Settings'))} › ${translate(section.label)}`
      : translate(msg('Settings'));
  }
  const find = (links: readonly (NavLink & { end?: boolean })[]) => {
    const to = activeLink(path, links);
    return to === null ? undefined : links.find((link) => link.to.split(/[?#]/)[0] === to);
  };
  const found =
    find([...navLinks(current.nav), ...current.app.footer]) ??
    others.map((app) => find(navLinks(app.nav))).find((link) => link && link.to !== '/') ??
    find(SUITE_PAGES);
  return translate(found?.label ?? (path === '/' ? msg('Home') : msg('Page')));
}

/** The app's name for the assistant: in Arabic with the English one ("مهام بيبول (Maham People)"). */
export function appName(app: SuiteApp, language: Language): string {
  return language === 'ar' ? `${app.nameAr} (${app.name})` : app.name;
}

/**
 * One line per app the person can open: its name, what it is for and its
 * sidebar, in the interface language (as the person sees it). A page two
 * apps list (Clients in Sales and in Books' Receivables) is named under
 * the first only, so put the open app first.
 */
export function guideLines(
  apps: readonly GuideApp[],
  translate: (key: string) => string,
  language: Language,
) {
  const split = apps.some((a) => a.app.id === 'sales');
  const seen = new Set<string>(['/']);
  const fresh = (link: NavLink) => {
    if (seen.has(link.to)) return false;
    seen.add(link.to);
    return true;
  };
  return apps.map(({ app, nav }) => {
    const pages = nav
      .flatMap((entry) => {
        if (entry.kind !== 'group') return fresh(entry) ? [translate(entry.label)] : [];
        const children = entry.children.filter(fresh).map((c) => translate(c.label));
        return children.length ? [`${translate(entry.label)} (${children.join(', ')})`] : [];
      })
      .join(', ');
    const about = app.id === 'books' && split ? ABOUT_FINANCE : ABOUT[app.id];
    return `- ${appName(app, language)}: ${about}.${pages ? ` Sidebar: ${pages}.` : ''}`;
  });
}

export function systemInstruction({
  place,
  guide,
  settings,
  wording = 'Settings › Language & wording',
}: {
  place: AiPlace;
  /** guideLines() of the apps the person can open. */
  guide: readonly string[];
  /** The sections of Settings, translated. */
  settings: readonly string[];
  /** The page of the words printed on documents, as the person sees it (pageLabel). */
  wording?: string;
}): string {
  const appLanguage = place.language === 'ar' ? 'Arabic' : 'English';
  return [
    "You are the Maham One assistant, built into Maham One (office apps for businesses in Kuwait), helping this company's team. Be helpful and concise: short answers, numbered steps.",
    `Answer in the language of the question (Arabic or English); if unclear, in ${appLanguage}, the app's language. Use KWD with 3 decimals (KD 1,250.500) and Kuwaiti practice (PIFSS, Civil ID, Friday-Saturday weekend; no VAT unless the company turned taxes on).`,
    "You can't see the person's records, documents or screen yet, only what they type and where they are. If an answer needs their data, ask them to describe it or paste only what is needed, and remind them not to paste Civil IDs, IBANs or salaries.",
    'For legal, labour-law or tax questions give general information and say to confirm with their lawyer or auditor.',
    "You can't act in the app: never say you did, changed, sent or saved anything. Say where to do it, naming the app, sidebar page and button as the guide does; if the guide doesn't have it, say you aren't sure.",
    '',
    'Where they are:',
    `App: ${place.app}`,
    `Page: ${place.page}`,
    `Path: ${place.path}`,
    `App language: ${appLanguage}`,
    `Role: ${place.role ? ROLE_NAMES[place.role] : 'not known'}`,
    '',
    `Guide (apps they can open; + New creates documents; Ctrl K searches; the grid button switches apps; the العربية / English button at the top switches the app's language (${wording} only sets words printed on documents); Home shows what needs attention):`,
    ...guide,
    `- Settings (bottom of each sidebar): ${settings.join(', ')}.`,
  ].join('\n');
}
