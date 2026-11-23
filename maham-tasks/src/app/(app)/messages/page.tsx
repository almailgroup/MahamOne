import { MessagesSquare } from "lucide-react";

import { EmptyState } from "@/components/ui/empty-state";
import { getI18n } from "@/lib/i18n/server";

/** Shown beside the list on a wide screen, when no thread is open. */
export default async function MessagesIndexPage() {
  const { t } = await getI18n();
  return (
    <div className="flex min-h-0 flex-1 items-center justify-center p-6">
      <EmptyState
        icon={<MessagesSquare />}
        title={t("dm.title")}
        description={t("dm.choose")}
      />
    </div>
  );
}
