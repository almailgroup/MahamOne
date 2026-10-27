import type { Metadata } from "next";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader, PageShell } from "@/components/layout/page-shell";
import { AddMemberDialog } from "@/components/team/add-member-dialog";
import { MemberActions } from "@/components/team/member-actions";
import { PersonMenu } from "@/components/people/person-menu";
import { RoleSelect } from "@/components/team/role-select";
import { PositionSelect } from "@/components/team/position-select";
import { Users } from "lucide-react";

import { roleMeta } from "@/lib/constants";
import { getI18n } from "@/lib/i18n/server";
import { getTeam, requireProfile } from "@/lib/data/queries";
import { hasServiceRole } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { signedInWithSecondStep } from "@/lib/auth/second-step";
import { TwoStepNeeded } from "@/components/team/two-step-needed";

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.team") };
}

export default async function TeamPage() {
  const { t, tn } = await getI18n();
  const [profile, team] = await Promise.all([requireProfile(), getTeam()]);
  const isAdmin = profile.role === "admin";
  // Both admin actions here need the service-role key; say so rather than
  // letting them fail on use.
  const serviceRole = hasServiceRole();
  // Adding people and changing roles wait for two-step sign-in.
  const twoStep = isAdmin ? await signedInWithSecondStep(await createClient()) : true;

  return (
    <PageShell width="wide">
      <PageHeader
        title={t("nav.team")}
        icon={<Users />}
        description={
          <>
            {t("team.membersIn", { members: tn("count.members", team.length) })}{" "}
            {isAdmin ? t("team.adminHint") : t("team.memberHint")}
          </>
        }
        actions={isAdmin ? <AddMemberDialog configured={serviceRole} /> : undefined}
      />

      {!twoStep && <TwoStepNeeded />}

      <Card className="stagger flex flex-col gap-1 p-1 sm:p-1.5">
        {team.map((member) => (
          <div
            key={member.id}
            className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2.5 rounded-[1.25rem] px-2.5 py-3 transition-colors hover:bg-foreground/[0.04] sm:gap-y-3 sm:p-3.5"
          >
            {/* The name and the face are the target. A person in a list
                reads as something you can act on, and this one was text. */}
            <PersonMenu person={member} me={profile}>
              <button
                type="button"
                className="flex min-w-0 flex-1 items-center gap-3 rounded-lg p-1 text-start transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                <Avatar>
                  {member.avatar_url && (
                    <AvatarImage src={member.avatar_url} alt="" />
                  )}
                  <AvatarFallback>
                    {initialsFrom(member.full_name, member.email)}
                  </AvatarFallback>
                </Avatar>
                <div className="min-w-0">
                  <p className="truncate text-[0.9375rem] font-medium">
                    {member.full_name ?? member.email}
                    {member.id === profile.id && (
                      <span className="ms-1.5 text-xs font-normal text-muted-foreground">
                        {t("common.you")}
                      </span>
                    )}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {member.email}
                  </p>
                  {!isAdmin && member.job_title && (
                    <p className="truncate text-xs text-muted-foreground">
                      {member.job_title}
                    </p>
                  )}
                </div>
              </button>
            </PersonMenu>

            {isAdmin ? (
              <div className="flex flex-wrap items-center gap-2">
                <PositionSelect
                  userId={member.id}
                  jobTitle={member.job_title}
                />
                <RoleSelect
                  userId={member.id}
                  role={member.role}
                  /* Guard against an admin removing their own last admin rights. */
                  disabled={member.id === profile.id}
                />
                {/* Your own password is changed from your profile, where it
                    asks for the current one first. */}
                {member.id !== profile.id && (
                  <MemberActions
                    userId={member.id}
                    name={member.full_name ?? member.email}
                    configured={serviceRole}
                  />
                )}
              </div>
            ) : (
              <Badge variant="outline">{t(roleMeta(member.role).label)}</Badge>
            )}
          </div>
        ))}
      </Card>
    </PageShell>
  );
}
