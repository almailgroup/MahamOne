import { redirect } from "next/navigation";

/**
 * There is no registering. The portal is for the company's staff, and
 * accounts are added by an admin from the Team page — the database refuses an
 * account nobody added (see the close_self_registration migration). The
 * address is kept so an old link or bookmark lands on sign-in, not on a 404.
 */
export default function RegisterPage(): never {
  redirect("/login");
}
