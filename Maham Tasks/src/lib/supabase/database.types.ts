/**
 * Typed shape of the `public` schema, matching supabase/migrations.
 *
 * Structured exactly like the output of `supabase gen types typescript`, so it
 * can be regenerated in place once the migrations are applied:
 *
 *   npx supabase gen types typescript --project-id <ref> --schema public \
 *     > src/lib/supabase/database.types.ts
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type UserRole = "admin" | "manager" | "member";
export type TaskStatus = "todo" | "in_progress" | "in_review" | "done";
export type TaskPriority = "low" | "medium" | "high" | "urgent";
/** The unit of a task's repeat rule. Null on the column means "once". */
export type RepeatUnit = "day" | "week" | "month" | "year";

export type AttachmentKind = "file" | "link";

export type ReminderChannel = "email" | "telegram" | "whatsapp" | "push";
export type ReminderKind = "assigned" | "due_soon" | "overdue" | "follow_up" | "summary";
export type ReminderStatus =
  | "pending"
  /** Claimed by a dispatcher run and being delivered right now. */
  | "sending"
  | "sent"
  | "failed"
  | "cancelled";

/** `notifications.type` — stored as text with a check constraint. */
export type NotificationType =
  | "task_assigned"
  | "task_unassigned"
  | "task_commented"
  | "task_mentioned"
  | "task_review_requested"
  | "task_completed"
  | "direct_message"
  | "reminder_failed"
  | "task_unblocked";

/** `task_activity.action` — stored as text with a check constraint. */
export type TaskActivityAction =
  | "created"
  | "updated"
  | "status_changed"
  | "priority_changed"
  | "due_date_changed"
  | "follow_up_set"
  | "follow_up_cleared"
  | "assignee_added"
  | "assignee_removed"
  | "commented"
  | "deleted"
  | "restored";

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          email: string;
          full_name: string | null;
          avatar_url: string | null;
          role: UserRole;
          /** Job position, assigned by an admin. */
          job_title: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          email: string;
          full_name?: string | null;
          avatar_url?: string | null;
          role?: UserRole;
          job_title?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          full_name?: string | null;
          avatar_url?: string | null;
          role?: UserRole;
          job_title?: string | null;
        };
        Relationships: [];
      };
      projects: {
        Row: {
          id: string;
          name: string;
          description: string | null;
          created_by: string | null;
          /** When it was archived, or null while it is live. */
          archived_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          description?: string | null;
          created_by: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          name?: string;
          description?: string | null;
          archived_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "projects_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      tasks: {
        Row: {
          id: string;
          /** NULL marks a general task, belonging to no project. */
          project_id: string | null;
          title: string;
          description: string | null;
          status: TaskStatus;
          priority: TaskPriority;
          /** Absolute instant, including time of day. */
          due_at: string | null;
          /** When this task should next be chased. */
          follow_up_at: string | null;
          follow_up_note: string | null;
          position: number;
          created_by: string | null;
          /** Set when trashed; cleared on restore. Hidden from every read. */
          deleted_at: string | null;
          /**
           * The repeat rule, or null for work that happens once. Closing a
           * repeating task opens the next one and takes the rule with it, so
           * a closed task never carries one.
           */
          repeat_every: RepeatUnit | null;
          /** How many of those units apart. 2 + "week" is fortnightly. */
          repeat_interval: number;
          /**
           * The milestone of its own project it counts towards. Optional
           * because it is absent until migration 44 has been run.
           */
          milestone_id?: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          project_id?: string | null;
          title: string;
          description?: string | null;
          status?: TaskStatus;
          priority?: TaskPriority;
          due_at?: string | null;
          follow_up_at?: string | null;
          follow_up_note?: string | null;
          position?: number;
          created_by: string;
          repeat_every?: RepeatUnit | null;
          repeat_interval?: number;
          milestone_id?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          title?: string;
          description?: string | null;
          status?: TaskStatus;
          priority?: TaskPriority;
          due_at?: string | null;
          follow_up_at?: string | null;
          follow_up_note?: string | null;
          position?: number;
          repeat_every?: RepeatUnit | null;
          repeat_interval?: number;
          milestone_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "tasks_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_milestone_id_fkey";
            columns: ["milestone_id"];
            referencedRelation: "project_milestones";
            referencedColumns: ["id"];
          },
        ];
      };
      task_assignments: {
        Row: {
          task_id: string;
          user_id: string;
          assigned_at: string;
        };
        Insert: {
          task_id: string;
          user_id: string;
          assigned_at?: string;
        };
        Update: {
          task_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_assignments_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_assignments_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      team_messages: {
        Row: {
          id: string;
          author_id: string;
          body: string;
          created_at: string;
          edited_at: string | null;
        };
        Insert: {
          id?: string;
          author_id: string;
          body: string;
          created_at?: string;
          edited_at?: string | null;
        };
        Update: {
          body?: string;
          edited_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "team_messages_author_id_fkey";
            columns: ["author_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      conversations: {
        Row: {
          id: string;
          created_at: string;
          last_message_at: string;
          member_low: string | null;
          member_high: string | null;
        };
        /** Opened through `start_direct_conversation`, never inserted directly. */
        Insert: never;
        Update: never;
        Relationships: [
          // Both point at profiles, which is exactly the ambiguity an embed
          // hint exists to resolve — declared so the check can see them.
          {
            foreignKeyName: "conversations_member_low_fkey";
            columns: ["member_low"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "conversations_member_high_fkey";
            columns: ["member_high"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      conversation_participants: {
        Row: {
          conversation_id: string;
          user_id: string;
          last_read_at: string;
        };
        Insert: never;
        Update: { last_read_at?: string };
        Relationships: [
          {
            foreignKeyName: "conversation_participants_conversation_id_fkey";
            columns: ["conversation_id"];
            referencedRelation: "conversations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "conversation_participants_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      direct_messages: {
        Row: {
          id: string;
          conversation_id: string;
          author_id: string;
          body: string;
          created_at: string;
          edited_at: string | null;
        };
        Insert: {
          id?: string;
          conversation_id: string;
          author_id: string;
          body: string;
          created_at?: string;
          edited_at?: string | null;
        };
        Update: {
          body?: string;
          edited_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "direct_messages_conversation_id_fkey";
            columns: ["conversation_id"];
            referencedRelation: "conversations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "direct_messages_author_id_fkey";
            columns: ["author_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      comments: {
        Row: {
          id: string;
          task_id: string;
          user_id: string | null;
          content: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          user_id: string;
          content: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          content?: string;
        };
        Relationships: [
          {
            foreignKeyName: "comments_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "comments_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Append-only audit trail. Written by database triggers only. */
      task_activity: {
        Row: {
          id: string;
          task_id: string;
          actor_id: string | null;
          action: TaskActivityAction;
          field: string | null;
          old_value: string | null;
          new_value: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [
          {
            foreignKeyName: "task_activity_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_activity_actor_id_fkey";
            columns: ["actor_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Who can see a project. Membership is the unit of project visibility. */
      project_members: {
        Row: {
          project_id: string;
          user_id: string;
          added_by: string | null;
          added_at: string;
        };
        Insert: {
          project_id: string;
          user_id: string;
          added_by?: string | null;
        };
        Update: never;
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_members_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          // The second route to profiles. Declaring it is what tells a reader
          // — and `supabase gen types` — that an embed here must name its key.
          {
            foreignKeyName: "project_members_added_by_fkey";
            columns: ["added_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Per-user reminder channel settings. One row per profile. */
      notification_preferences: {
        Row: {
          user_id: string;
          email_enabled: boolean;
          telegram_enabled: boolean;
          whatsapp_enabled: boolean;
          /** Reminders to the devices in push_subscriptions. */
          push_enabled: boolean;
          telegram_chat_id: string | null;
          whatsapp_number: string | null;
          telegram_link_code: string | null;
          remind_assigned: boolean;
          remind_due_soon: boolean;
          remind_overdue: boolean;
          remind_follow_up: boolean;
          /** Absent until migration 37 has been run. */
          morning_summary?: boolean;
          due_soon_lead_hours: number;
          created_at: string;
          updated_at: string;
        };
        Insert: { user_id: string };
        Update: {
          email_enabled?: boolean;
          telegram_enabled?: boolean;
          whatsapp_enabled?: boolean;
          push_enabled?: boolean;
          telegram_chat_id?: string | null;
          whatsapp_number?: string | null;
          telegram_link_code?: string | null;
          remind_assigned?: boolean;
          remind_due_soon?: boolean;
          remind_overdue?: boolean;
          remind_follow_up?: boolean;
          morning_summary?: boolean;
          due_soon_lead_hours?: number;
        };
        Relationships: [
          {
            foreignKeyName: "notification_preferences_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /**
       * Faults from the deployed app, kept for two weeks.
       *
       * Write-only for everybody: there is no select policy, because a
       * message can carry a fragment of whatever it failed on. An admin
       * reads them through `recent_errors()`.
       */
      app_errors: {
        Row: {
          id: string;
          occurred_at: string;
          user_id: string | null;
          source: "browser" | "server";
          digest: string | null;
          message: string;
          route: string | null;
          user_agent: string | null;
        };
        Insert: {
          user_id?: string | null;
          source: "browser" | "server";
          digest?: string | null;
          message: string;
          route?: string | null;
          user_agent?: string | null;
        };
        Update: never;
        Relationships: [
          {
            foreignKeyName: "app_errors_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** The small steps inside a task, under the task's own rules. */
      task_checklist_items: {
        Row: {
          id: string;
          task_id: string;
          content: string;
          done: boolean;
          position: number;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          content: string;
          done?: boolean;
          position?: number;
          created_by?: string | null;
        };
        Update: {
          content?: string;
          done?: boolean;
          position?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_checklist_items_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_checklist_items_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Who reacted to which comment, with one of five fixed emoji. */
      comment_reactions: {
        Row: {
          comment_id: string;
          user_id: string;
          emoji: string;
          created_at: string;
        };
        Insert: {
          comment_id: string;
          user_id: string;
          emoji: string;
        };
        Update: Record<string, never>;
        Relationships: [
          {
            foreignKeyName: "comment_reactions_comment_id_fkey";
            columns: ["comment_id"];
            referencedRelation: "comments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "comment_reactions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** What the person running a project says about how it is going. */
      project_status_updates: {
        Row: {
          id: string;
          project_id: string;
          author_id: string | null;
          status: ProjectStatus;
          body: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          project_id: string;
          author_id: string;
          status: ProjectStatus;
          body: string;
        };
        /** Append-only: there is no update policy and no update grant. */
        Update: Record<string, never>;
        Relationships: [
          {
            foreignKeyName: "project_status_updates_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_status_updates_author_id_fkey";
            columns: ["author_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** One row per device that has agreed to notifications. */
      company_holidays: {
        Row: {
          day: string;
          name: string;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          day: string;
          name: string;
          created_by?: string | null;
        };
        Update: {
          name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "company_holidays_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      task_templates: {
        Row: {
          id: string;
          name: string;
          title: string;
          description: string | null;
          priority: TaskPriority;
          steps: string[];
          label_ids: string[];
          due_in_working_days: number | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          title: string;
          description?: string | null;
          priority?: TaskPriority;
          steps?: string[];
          label_ids?: string[];
          due_in_working_days?: number | null;
          created_by?: string | null;
        };
        Update: {
          name?: string;
          title?: string;
          description?: string | null;
          priority?: TaskPriority;
          steps?: string[];
          label_ids?: string[];
          due_in_working_days?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "task_templates_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      admin_alerts: {
        Row: {
          id: string;
          sent_at: string;
          faults: number;
          failures: number;
          reached: number;
        };
        Insert: {
          id?: string;
          sent_at?: string;
          faults?: number;
          failures?: number;
          reached?: number;
        };
        Update: Record<never, never>;
        Relationships: [];
      };
      project_milestones: {
        Row: {
          id: string;
          project_id: string;
          title: string;
          /** A calendar day, "2026-11-05": a date promised, not an instant. */
          due_on: string;
          /** When somebody marked it reached, or null. */
          done_at: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          project_id: string;
          title: string;
          due_on: string;
          done_at?: string | null;
          created_by?: string | null;
        };
        Update: {
          title?: string;
          due_on?: string;
          done_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "project_milestones_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "project_milestones_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      task_dependencies: {
        Row: {
          task_id: string;
          blocked_by: string;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          task_id: string;
          blocked_by: string;
          created_by?: string | null;
        };
        Update: Record<never, never>;
        Relationships: [
          {
            foreignKeyName: "task_dependencies_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_dependencies_blocked_by_fkey";
            columns: ["blocked_by"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_dependencies_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      labels: {
        Row: {
          id: string;
          name: string;
          colour: LabelColour;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          colour?: LabelColour;
          created_by?: string | null;
        };
        Update: {
          name?: string;
          colour?: LabelColour;
        };
        Relationships: [
          {
            foreignKeyName: "labels_created_by_fkey";
            columns: ["created_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      task_labels: {
        Row: {
          task_id: string;
          label_id: string;
          created_at: string;
        };
        Insert: {
          task_id: string;
          label_id: string;
        };
        Update: Record<never, never>;
        Relationships: [
          {
            foreignKeyName: "task_labels_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_labels_label_id_fkey";
            columns: ["label_id"];
            referencedRelation: "labels";
            referencedColumns: ["id"];
          },
        ];
      };
      push_subscriptions: {
        Row: {
          id: string;
          user_id: string;
          /** The push service's address for this device. Unique everywhere. */
          endpoint: string;
          p256dh: string;
          auth: string;
          user_agent: string | null;
          created_at: string;
          last_used_at: string | null;
        };
        Insert: {
          id?: string;
          user_id: string;
          endpoint: string;
          p256dh: string;
          auth: string;
          user_agent?: string | null;
          last_used_at?: string | null;
        };
        Update: {
          user_agent?: string | null;
          last_used_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /**
       * The VAPID pair, one row forever.
       *
       * Reachable only with the service role: row-level security is on and
       * there are no policies, so a user session sees nothing here.
       */
      web_push_keys: {
        Row: {
          id: boolean;
          public_key: string;
          private_key: string;
          created_at: string;
        };
        Insert: {
          id?: boolean;
          public_key: string;
          private_key: string;
        };
        Update: { public_key?: string; private_key?: string };
        Relationships: [];
      };
      /** Outbound reminders. Written by the scheduler, drained by the dispatcher. */
      reminder_queue: {
        Row: {
          claimed_at: string | null;
          id: string;
          user_id: string;
          task_id: string | null;
          channel: ReminderChannel;
          kind: ReminderKind;
          recipient: string;
          subject: string | null;
          body: string;
          status: ReminderStatus;
          attempts: number;
          last_error: string | null;
          dedupe_key: string;
          scheduled_for: string;
          sent_at: string | null;
          /** When delivery was given up on. Null until it is. */
          failed_at: string | null;
          created_at: string;
        };
        Insert: never;
        Update: {
          status?: ReminderStatus;
          attempts?: number;
          last_error?: string | null;
          sent_at?: string | null;
          failed_at?: string | null;
          scheduled_for?: string;
          claimed_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "reminder_queue_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "reminder_queue_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      task_attachments: {
        Row: {
          id: string;
          task_id: string;
          uploaded_by: string | null;
          kind: AttachmentKind;
          name: string;
          storage_path: string | null;
          url: string | null;
          mime_type: string | null;
          size_bytes: number | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          uploaded_by: string;
          kind: AttachmentKind;
          name: string;
          storage_path?: string | null;
          url?: string | null;
          mime_type?: string | null;
          size_bytes?: number | null;
        };
        Update: never;
        Relationships: [
          {
            foreignKeyName: "task_attachments_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_attachments_uploaded_by_fkey";
            columns: ["uploaded_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Private to each recipient. Rows are written only by database triggers. */
      notifications: {
        Row: {
          id: string;
          user_id: string;
          actor_id: string | null;
          type: NotificationType;
          title: string;
          body: string | null;
          task_id: string | null;
          project_id: string | null;
          conversation_id: string | null;
          read_at: string | null;
          created_at: string;
        };
        Insert: never;
        Update: { read_at?: string | null };
        Relationships: [
          {
            foreignKeyName: "notifications_task_id_fkey";
            columns: ["task_id"];
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_project_id_fkey";
            columns: ["project_id"];
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_conversation_id_fkey";
            columns: ["conversation_id"];
            referencedRelation: "conversations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          // Recipient and actor are both profiles, hence the hint in the query.
          {
            foreignKeyName: "notifications_actor_id_fkey";
            columns: ["actor_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      personal_notes: {
        Row: {
          id: string;
          user_id: string;
          title: string;
          body: string;
          pinned: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          title?: string;
          body?: string;
          pinned?: boolean;
        };
        Update: {
          title?: string;
          body?: string;
          pinned?: boolean;
        };
        Relationships: [
          {
            foreignKeyName: "personal_notes_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      /** Who a personal list has been shared with. */
      personal_note_shares: {
        Row: {
          note_id: string;
          user_id: string;
          added_by: string | null;
          added_at: string;
        };
        Insert: {
          note_id: string;
          user_id: string;
          added_by?: string | null;
        };
        Update: never;
        Relationships: [
          {
            foreignKeyName: "personal_note_shares_note_id_fkey";
            columns: ["note_id"];
            referencedRelation: "personal_notes";
            referencedColumns: ["id"];
          },
          // Two routes to profiles, so an embed here has to name its key.
          {
            foreignKeyName: "personal_note_shares_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "personal_note_shares_added_by_fkey";
            columns: ["added_by"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      personal_note_items: {
        Row: {
          id: string;
          note_id: string;
          user_id: string;
          content: string;
          done: boolean;
          position: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          note_id: string;
          user_id: string;
          content?: string;
          done?: boolean;
          position?: number;
        };
        Update: {
          content?: string;
          done?: boolean;
          position?: number;
        };
        Relationships: [
          {
            foreignKeyName: "personal_note_items_note_id_fkey";
            columns: ["note_id"];
            referencedRelation: "personal_notes";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "personal_note_items_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: Record<never, never>;
    Functions: {
      current_user_role: { Args: Record<never, never>; Returns: UserRole };
      is_admin: { Args: Record<never, never>; Returns: boolean };
      is_manager_or_admin: { Args: Record<never, never>; Returns: boolean };
      can_edit_task: { Args: { task: string }; Returns: boolean };
      can_view_project: { Args: { project: string }; Returns: boolean };
      can_view_note: { Args: { note: string }; Returns: boolean };
      owns_note: { Args: { note: string }; Returns: boolean };
      can_view_task: { Args: { task: string }; Returns: boolean };
      in_conversation: { Args: { conversation: string }; Returns: boolean };
      /** Finds the thread with somebody, or opens it. Returns its id. */
      start_direct_conversation: { Args: { other: string }; Returns: string };
      /** Every thread you are in, with its last line and unread count. */
      my_conversations: {
        Args: Record<never, never>;
        Returns: {
          id: string;
          last_message_at: string;
          other_id: string | null;
          other_name: string | null;
          other_email: string | null;
          other_avatar: string | null;
          other_title: string | null;
          last_message: string | null;
          last_author_id: string | null;
          unread: number;
        }[];
      };
      unread_direct_count: { Args: Record<never, never>; Returns: number };
      enqueue_task_reminders: { Args: Record<never, never>; Returns: number };
      /** One summary per person and channel for this office morning. */
      enqueue_morning_summaries: { Args: { as_of?: string }; Returns: number };
      /** The Reports page's numbers, over what the caller can see. */
      /** Service key only (migration 45). */
      admin_alert_digest: {
        Args: { as_of?: string };
        Returns: {
          since: string;
          faults: number;
          pages: { source: "browser" | "server"; page: string; count: number }[];
          failedReminders: number;
          recipients: string[];
        };
      };
      work_report: {
        Args: { first_day: string; last_day: string; grain?: string };
        Returns: unknown;
      };
      /** Work sent to the bot by a linked chat, added as that person's. */
      add_from_chat: {
        Args: {
          chat: string;
          item_title: string;
          item_detail?: string | null;
          item_priority?: TaskPriority;
          due?: string | null;
        };
        Returns: { kind: "task" | "note"; id: string } | null;
      };
      /** Moves a batch of due reminders to 'sending' and returns them. */
      claim_reminders: {
        Args: { batch_size?: number };
        Returns: Database["public"]["Tables"]["reminder_queue"]["Row"][];
      };
      /** The same claim, narrowed to one task, for the assignment path. */
      claim_task_reminders: {
        Args: { task: string };
        Returns: Database["public"]["Tables"]["reminder_queue"]["Row"][];
      };
      /** Per-assignee open/done/overdue, counted in the database. */
      /** Soft delete: hides the task everywhere, keeps it for 30 days. */
      trash_task: { Args: { task: string }; Returns: boolean };
      restore_task: { Args: { task: string }; Returns: boolean };
      /** Hard-deletes tasks trashed longer ago than the interval. */
      purge_trashed_tasks: { Args: { older_than?: string }; Returns: number };
      workload_counts: {
        Args: Record<never, never>;
        Returns: {
          user_id: string;
          open: number;
          done: number;
          overdue: number;
        }[];
      };
      /**
       * Dashboard figures, counted in the database under the caller's RLS.
       * `tz` is an IANA timezone so "due today" means the viewer's day.
       */
      /** Tells somebody a reminder could not be delivered. Dispatcher only. */
      notify_reminder_failed: { Args: { reminder: string }; Returns: void };
      /** Recent undeliverable reminders across the team. Admins only. */
      reminder_failures: {
        Args: { since_hours?: number };
        Returns: {
          user_id: string;
          person: string;
          channel: ReminderChannel;
          kind: string;
          attempts: number;
          last_error: string | null;
          failed_at: string;
        }[];
      };
      /** The same question about yourself, which anybody may ask. */
      my_reminder_failures: {
        Args: { since_hours?: number };
        Returns: {
          channel: ReminderChannel;
          kind: string;
          attempts: number;
          last_error: string | null;
          failed_at: string;
        }[];
      };
      /** Archives a project or brings it back; refuses while work is open. */
      set_project_archived: {
        Args: { project: string; archived: boolean };
        Returns: void;
      };
      /** Recent faults, grouped. Admins only; raises for anybody else. */
      project_health: {
        Args: Record<string, never>;
        Returns: {
          project_id: string;
          name: string;
          latest_status: ProjectStatus | null;
          latest_body: string | null;
          latest_at: string | null;
          latest_author: string | null;
          open_tasks: number;
          overdue_tasks: number;
        }[];
      };
      recent_errors: {
        Args: { since_hours?: number };
        Returns: {
          occurred_at: string;
          person: string | null;
          source: "browser" | "server";
          digest: string | null;
          message: string;
          route: string | null;
          seen: number;
        }[];
      };
      /** Drops error rows older than the given age. */
      purge_old_errors: { Args: { older_than?: string }; Returns: number };
      task_counts: {
        Args: { tz?: string };
        Returns: {
          total: number;
          done: number;
          todo: number;
          in_progress: number;
          in_review: number;
          overdue: number;
          due_today: number;
        }[];
      };
    };
    Enums: {
      user_role: UserRole;
      task_status: TaskStatus;
      task_priority: TaskPriority;
    };
    CompositeTypes: Record<never, never>;
  };
};

/** Convenience row aliases used throughout the app. */
export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
export type Project = Database["public"]["Tables"]["projects"]["Row"];
export type CompanyHoliday = Database["public"]["Tables"]["company_holidays"]["Row"];
/** The dot beside a label's name. No amber: that means late, and only that. */
export type LabelColour = "slate" | "blue" | "green" | "violet" | "pink" | "teal";
export type Label = Database["public"]["Tables"]["labels"]["Row"];
export type TaskTemplate = Database["public"]["Tables"]["task_templates"]["Row"];
export type ProjectMilestone = Database["public"]["Tables"]["project_milestones"]["Row"];
export type Task = Database["public"]["Tables"]["tasks"]["Row"];
export type TaskAssignment =
  Database["public"]["Tables"]["task_assignments"]["Row"];
export type Comment = Database["public"]["Tables"]["comments"]["Row"];
export type TaskActivity = Database["public"]["Tables"]["task_activity"]["Row"];
export type TaskAttachment =
  Database["public"]["Tables"]["task_attachments"]["Row"];
export type Notification = Database["public"]["Tables"]["notifications"]["Row"];
export type ProjectMember =
  Database["public"]["Tables"]["project_members"]["Row"];
export type NotificationPreferences =
  Database["public"]["Tables"]["notification_preferences"]["Row"];
export type ReminderQueueRow =
  Database["public"]["Tables"]["reminder_queue"]["Row"];

export type PushSubscriptionRow =
  Database["public"]["Tables"]["push_subscriptions"]["Row"];

/** What the profile page shows about a device. Never the keys. */
export type PushDevice = Pick<
  PushSubscriptionRow,
  "endpoint" | "user_agent" | "created_at"
>;

/** A reminder that could not be delivered — never the message itself. */
export type ReminderFailure =
  Database["public"]["Functions"]["my_reminder_failures"]["Returns"][number];

export type TeamReminderFailure =
  Database["public"]["Functions"]["reminder_failures"]["Returns"][number];

/** A fault, as an admin sees it: grouped, counted, never a payload. */
export type AppError =
  Database["public"]["Functions"]["recent_errors"]["Returns"][number];

/** How the person running a project says it is going. */
export type ProjectStatus = "on_track" | "at_risk" | "off_track";

export type ProjectStatusUpdate =
  Database["public"]["Tables"]["project_status_updates"]["Row"];

/** An update with whoever wrote it, which is how the project page lists them. */
export type ProjectStatusUpdateWithAuthor = ProjectStatusUpdate & {
  author: Pick<Profile, "id" | "full_name" | "email" | "avatar_url"> | null;
};

/** One live project's health, as project_health() reports it. */
export type ProjectHealthRow =
  Database["public"]["Functions"]["project_health"]["Returns"][number];

export type ChecklistItem =
  Database["public"]["Tables"]["task_checklist_items"]["Row"];

/** How far along a task's steps are, for a list that has no room for them. */
export type ChecklistProgress = { done: number; total: number };

export type Conversation = Database["public"]["Tables"]["conversations"]["Row"];
export type ConversationParticipant =
  Database["public"]["Tables"]["conversation_participants"]["Row"];
export type DirectMessage =
  Database["public"]["Tables"]["direct_messages"]["Row"];

/** A message with whoever wrote it, which is what the thread renders. */
export type DirectMessageWithAuthor = DirectMessage & { author: Profile | null };

/**
 * The other person, as the conversation list needs them.
 *
 * Not a whole `Profile`: the list draws a name, a picture and a job title,
 * and asking the database for the rest of a profile per thread is work
 * nobody looks at.
 */
export type ConversationPeer = {
  id: string;
  full_name: string | null;
  email: string | null;
  avatar_url: string | null;
  job_title: string | null;
};

/**
 * A thread as the list shows it: who it is with, what was said last, and how
 * much of it you have not read.
 */
export type ConversationSummary = {
  id: string;
  lastMessageAt: string;
  /** The other person. Null only if their account has since been deleted. */
  other: ConversationPeer | null;
  lastMessage: string | null;
  lastAuthorId: string | null;
  unread: number;
};

export type PersonalNote =
  Database["public"]["Tables"]["personal_notes"]["Row"];
export type PersonalNoteItem =
  Database["public"]["Tables"]["personal_note_items"]["Row"];

/** A note with its checklist, in display order. */
export type PersonalNoteShare =
  Database["public"]["Tables"]["personal_note_shares"]["Row"];

/**
 * A list with everything the page shows: its lines, who owns it, and who else
 * is on it. `mine` saves every component re-deriving the same comparison.
 */
export type NoteWithItems = PersonalNote & {
  items: PersonalNoteItem[];
  owner: Profile | null;
  collaborators: Profile[];
  mine: boolean;
};

/** A notification joined with the person who caused it. */
export type NotificationWithActor = Notification & { actor: Profile | null };

/** A task joined with the profiles assigned to it. */
export type TaskWithAssignees = Task & {
  assignees: Profile[];
  /** The labels on it, by id; names and colours come from LabelsProvider. */
  labelIds: string[];
  /** How many open tasks it waits on; 0 when nothing holds it up. */
  waitingOn: number;
  /**
   * How far along its steps are.
   *
   * Carried on every task because a list is where it is worth seeing — "3 of
   * 5" on a card says more about whether something is nearly done than its
   * status does. Only the flag is fetched, not the text, so a board of forty
   * tasks costs forty booleans rather than forty lists.
   */
  checklist: ChecklistProgress;
};

/** A comment joined with its author (null when the account was removed). */
export type TeamMessage = Database["public"]["Tables"]["team_messages"]["Row"];

/** A message with whoever wrote it, which is how the room reads. */
export type TeamMessageWithAuthor = TeamMessage & { author: Profile | null };

export type CommentWithAuthor = Comment & {
  author: Profile | null;
  /** Who reacted, and with what. Empty on a comment nobody has reacted to. */
  reactions: { emoji: string; user_id: string }[];
};

/** An activity row joined with the profile that caused it. */
export type TaskActivityWithActor = TaskActivity & { actor: Profile | null };
