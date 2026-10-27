import { notFound } from "next/navigation";

import { DirectThread } from "@/components/messages/direct-thread";
import {
  getConversationPartner,
  getDirectMessages,
  requireProfile,
} from "@/lib/data/queries";

export default async function ConversationPage({
  params,
}: {
  params: Promise<{ conversationId: string }>;
}) {
  const { conversationId } = await params;

  const [profile, messages, partner] = await Promise.all([
    requireProfile(),
    getDirectMessages(conversationId),
    getConversationPartner(conversationId),
  ]);

  // Null means row-level security did not hand it over. A conversation you
  // are not in and one that does not exist should look the same from outside:
  // "no such conversation" either way, never "it exists but not for you".
  if (messages === null) notFound();

  return (
    <DirectThread
      conversationId={conversationId}
      me={profile}
      partner={partner}
      initial={messages}
    />
  );
}
