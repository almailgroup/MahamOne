/**
 * The workspace the end-to-end specs run against.
 *
 * Six people, six projects and a month of tasks around a fixed "today", so a
 * spec can say "the overdue list holds three" and still be true next year.
 * Nothing here is real: the names are the ones the screenshots in the README
 * use, and every id is a literal so a failing assertion names something a
 * person can find.
 */

export const IDS = {
  admin: "00000000-0000-4000-8000-000000000001",
  sara: "00000000-0000-4000-8000-000000000002",
  omar: "00000000-0000-4000-8000-000000000003",
  priya: "00000000-0000-4000-8000-000000000004",
  yusuf: "00000000-0000-4000-8000-000000000005",
  lina: "00000000-0000-4000-8000-000000000006",
  /** Signs in with an authenticator app; only the two-step spec uses her. */
  huda: "00000000-0000-4000-8000-000000000007",
};

/** The instant the seeded board is built around. */
export const NOW = "2026-09-21T09:00:00.000Z";

const person = (id, name, email, role, title) => ({
  id,
  email,
  full_name: name,
  role,
  avatar_url: null,
  job_title: title,
  telegram_chat_id: null,
  whatsapp_number: null,
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
});

const day = (offsetDays, hour = 13) => {
  const base = new Date(NOW);
  base.setUTCDate(base.getUTCDate() + offsetDays);
  base.setUTCHours(hour, 0, 0, 0);
  return base.toISOString();
};

export function seed() {
  const profiles = [
    person(IDS.admin, "Admin", "admin@almailgroup.com", "admin", "Director"),
    person(IDS.sara, "Sara Khan", "sara@almailgroup.com", "manager", "Operations Manager"),
    person(IDS.omar, "Omar Haddad", "omar@almailgroup.com", "member", "Accountant"),
    person(IDS.priya, "Priya Nair", "priya@almailgroup.com", "member", "Designer"),
    person(IDS.yusuf, "Yusuf Rahman", "yusuf@almailgroup.com", "member", "Logistics"),
    person(IDS.lina, "Lina Aboud", "lina@almailgroup.com", "member", "Marketing"),
    person(IDS.huda, "Huda Saleh", "huda@almailgroup.com", "member", "Reception"),
  ];

  const projects = [
    { id: "11111111-1111-4111-8111-000000000001", name: "Kuwait Bank Portal", description: "Corporate banking rollout." },
    { id: "11111111-1111-4111-8111-000000000002", name: "Warehouse Move", description: "Shuwaikh to Sulaibiya." },
    { id: "11111111-1111-4111-8111-000000000003", name: "Brand Refresh", description: "Signage, cards, site." },
    // Finished last year, kept for the record: out of the sidebar, still
    // readable, and a spec can check both halves of that.
    { id: "11111111-1111-4111-8111-000000000004", name: "2025 Audit", description: "Closed.", archived_at: "2026-01-15T00:00:00Z" },
  ].map((p) => ({
    ...p,
    colour: null,
    archived_at: p.archived_at ?? null,
    created_by: IDS.admin,
    created_at: "2026-02-01T00:00:00Z",
    updated_at: "2026-02-01T00:00:00Z",
  }));

  /**
   * [title, status, priority, project index, due offset in days, assignee,
   *  repeat unit]
   */
  const shape = [
    ["Sign the custody agreement", "todo", "urgent", 0, -3, IDS.sara],
    ["Chase the QR code artwork", "in_progress", "high", 2, -1, IDS.priya],
    ["Reconcile August freight", "todo", "medium", 1, -2, IDS.omar, "month"],
    ["Meet with Kuwait banks", "todo", "high", 0, 0, IDS.admin],
    ["Container MSKU4471 clearance", "in_progress", "urgent", 1, 0, IDS.yusuf],
    ["Draft the September invoice", "in_review", "medium", 1, 0, IDS.omar],
    ["Camera installation", "todo", "low", 1, 3, IDS.yusuf],
    ["New letterhead proof", "in_review", "medium", 2, 5, IDS.priya],
    ["Staff parking list", "todo", "low", 1, 9, IDS.lina],
    ["Quarterly board pack", "done", "high", 0, -8, IDS.sara],
    ["Archive 2025 contracts", "done", "low", 0, -14, IDS.omar],
    ["Website copy review", "todo", "medium", 2, null, IDS.lina],
    // Next month, so a spec can turn the calendar to it and find something.
    ["October board meeting", "todo", "high", 0, 20, IDS.admin],
  ];

  const tasks = [];
  const task_assignments = [];
  shape.forEach(([title, status, priority, projectIndex, due, assignee, repeat], index) => {
    const id = `22222222-2222-4222-8222-${String(index + 1).padStart(12, "0")}`;
    tasks.push({
      id,
      title,
      description: null,
      status,
      priority,
      project_id: projects[projectIndex].id,
      created_by: IDS.admin,
      due_at: due === null ? null : day(due),
      follow_up_at: null,
      position: index,
      deleted_at: null,
      repeat_every: repeat ?? null,
      repeat_interval: 1,
      milestone_id: null,
      created_at: "2026-09-01T00:00:00Z",
      updated_at: "2026-09-01T00:00:00Z",
    });
    task_assignments.push({
      id: `33333333-3333-4333-8333-${String(index + 1).padStart(12, "0")}`,
      task_id: id,
      user_id: assignee,
      created_at: "2026-09-01T00:00:00Z",
    });
  });

  // The warehouse move's next promise, with two of its tasks under it.
  const project_milestones = [
    {
      id: "88888888-8888-4888-8888-000000000001",
      project_id: projects[1].id,
      title: "Sulaibiya keys handed over",
      due_on: day(12).slice(0, 10),
      done_at: null,
      created_by: IDS.admin,
      created_at: "2026-09-01T00:00:00Z",
      updated_at: "2026-09-01T00:00:00Z",
    },
  ];
  for (const title of ["Camera installation", "Staff parking list"]) {
    tasks.find((task) => task.title === title).milestone_id = project_milestones[0].id;
  }

  const team_messages = [
    { id: "44444444-4444-4444-8444-000000000001", author_id: IDS.sara, body: "Morning all — the Kuwait bank meeting moved to 3pm.", created_at: "2026-09-20T06:10:00Z", edited_at: null },
    { id: "44444444-4444-4444-8444-000000000002", author_id: IDS.omar, body: "Noted. The September numbers are in the sheet.", created_at: "2026-09-20T06:26:00Z", edited_at: null },
    { id: "44444444-4444-4444-8444-000000000003", author_id: IDS.admin, body: "I will take the QR code task this evening.", created_at: "2026-09-20T12:40:00Z", edited_at: null },
  ];

  const conversations = [
    {
      id: "55555555-5555-4555-8555-000000000001",
      member_low: IDS.admin < IDS.sara ? IDS.admin : IDS.sara,
      member_high: IDS.admin < IDS.sara ? IDS.sara : IDS.admin,
      created_at: "2026-09-19T08:00:00Z",
      last_message_at: "2026-09-20T15:30:00Z",
    },
  ];

  const conversation_participants = [
    { conversation_id: conversations[0].id, user_id: IDS.admin, last_read_at: "2026-09-20T15:31:00Z" },
    { conversation_id: conversations[0].id, user_id: IDS.sara, last_read_at: "2026-09-20T15:31:00Z" },
  ];

  const direct_messages = [
    { id: "66666666-6666-4666-8666-000000000001", conversation_id: conversations[0].id, author_id: IDS.sara, body: "Can you approve the custody agreement today?", created_at: "2026-09-20T15:29:00Z", edited_at: null },
    { id: "66666666-6666-4666-8666-000000000002", conversation_id: conversations[0].id, author_id: IDS.admin, body: "Reading it now.", created_at: "2026-09-20T15:30:00Z", edited_at: null },
  ];

  return {
    profiles,
    projects,
    tasks,
    task_assignments,
    team_messages,
    conversations,
    conversation_participants,
    direct_messages,
    project_members: [],
    notifications: [],
    // One project its manager has already called at risk, so the dashboard's
    // "needs attention" has something in it before any spec posts.
    project_status_updates: [
      {
        id: "88888888-8888-4888-8888-000000000001",
        project_id: projects[1].id,
        author_id: IDS.sara,
        status: "at_risk",
        body: "Sulaibiya racking is a week late; the move date holds only if it lands by Thursday.",
        created_at: day(-3),
      },
    ],
    personal_notes: [],
    personal_note_items: [],
    personal_note_shares: [],
    // Two steps on the bank meeting, one of them done, so a spec can check
    // both the panel and the "1/2" a list shows.
    task_checklist_items: [
      {
        id: "99999999-9999-4999-8999-000000000001",
        task_id: "22222222-2222-4222-8222-000000000004",
        content: "Bring the signatory list",
        done: true,
        position: 0,
        created_by: IDS.admin,
        created_at: "2026-09-01T00:00:00Z",
        updated_at: "2026-09-01T00:00:00Z",
      },
      {
        id: "99999999-9999-4999-8999-000000000002",
        task_id: "22222222-2222-4222-8222-000000000004",
        content: "Bring the trade licence",
        done: false,
        position: 1024,
        created_by: IDS.admin,
        created_at: "2026-09-01T00:00:00Z",
        updated_at: "2026-09-01T00:00:00Z",
      },
    ],
    // One fault, seen twice, so a spec can check the grouping and that only
    // an admin is shown it.
    app_errors: [
      {
        id: "88888888-8888-4888-8888-000000000001",
        occurred_at: "2026-09-21T07:14:00Z",
        user_id: IDS.priya,
        source: "browser",
        digest: "3f2a91",
        message: "TypeError: Cannot read properties of null",
        route: "/tasks?filter=overdue",
        user_agent: "iPhone",
      },
      {
        id: "88888888-8888-4888-8888-000000000002",
        occurred_at: "2026-09-21T07:16:00Z",
        user_id: IDS.priya,
        source: "browser",
        digest: "3f2a91",
        message: "TypeError: Cannot read properties of null",
        route: "/tasks?filter=overdue",
        user_agent: "iPhone",
      },
    ],
    comments: [],
    comment_reactions: [],
    task_activity: [],
    task_attachments: [],
    notification_preferences: [
      {
        user_id: IDS.admin,
        email_enabled: true,
        telegram_enabled: false,
        whatsapp_enabled: false,
        push_enabled: false,
        telegram_chat_id: null,
        whatsapp_number: null,
        telegram_link_code: null,
        remind_assigned: true,
        remind_due_soon: true,
        remind_overdue: true,
        remind_follow_up: true,
        morning_summary: false,
        due_soon_lead_hours: 24,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-01T00:00:00Z",
      },
    ],
    push_subscriptions: [],
    web_push_keys: [],
    company_holidays: [],
    // Two labels, one of them on the bank meeting.
    labels: [
      { id: "99999999-9999-4999-8999-000000000001", name: "Bank", colour: "blue", created_by: IDS.admin, created_at: "2026-09-01T00:00:00Z" },
      { id: "99999999-9999-4999-8999-000000000002", name: "Ministry", colour: "green", created_by: IDS.admin, created_at: "2026-09-01T00:00:00Z" },
    ],
    task_dependencies: [],
    project_milestones,
    task_templates: [
      {
        id: "44444444-4444-4444-8444-0000000000a1",
        name: "Month-end payroll",
        title: "Run payroll",
        description: "Salaries for the month, through the bank portal.",
        priority: "high",
        steps: ["Collect timesheets", "Check overtime", "Send to the bank"],
        label_ids: ["99999999-9999-4999-8999-000000000001"],
        due_in_working_days: 3,
        created_by: IDS.admin,
        created_at: "2026-09-01T00:00:00Z",
        updated_at: "2026-09-01T00:00:00Z",
      },
    ],
    task_labels: [
      {
        task_id: tasks.find((task) => task.title === "Meet with Kuwait banks").id,
        label_id: "99999999-9999-4999-8999-000000000001",
        created_at: "2026-09-01T00:00:00Z",
      },
    ],
    // Huda signs in with an authenticator app; nobody else has one yet.
    mfa_factors: [
      {
        id: "88888888-8888-4888-8888-000000000001",
        user_id: IDS.huda,
        friendly_name: "Authenticator app",
        factor_type: "totp",
        status: "verified",
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-01T00:00:00Z",
      },
    ],
    // One undeliverable reminder, to somebody who is not the admin: enough
    // for a spec to check that an admin sees the team's and a member sees
    // neither theirs nor anybody else's.
    reminder_queue: [
      {
        id: "77777777-7777-4777-8777-000000000001",
        user_id: IDS.sara,
        task_id: null,
        channel: "whatsapp",
        kind: "due_soon",
        recipient: "+96500000000",
        subject: "Due soon: Sign the custody agreement",
        body: "Sign the custody agreement is due.",
        dedupe_key: "seed:failed:1",
        status: "failed",
        attempts: 4,
        last_error: "Twilio 400: not a WhatsApp number",
        scheduled_for: "2026-09-20T06:00:00Z",
        claimed_at: null,
        sent_at: null,
        failed_at: "2026-09-20T06:20:00Z",
        created_at: "2026-09-20T06:00:00Z",
      },
    ],
  };
}
