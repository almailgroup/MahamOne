import { redirect } from "next/navigation";

/**
 * There is no registering here. Accounts are Maham One's, and a Maham Tasks
 * admin adds people from the Team page (tasks.add_teammate): an account
 * nobody added has no profile in Maham Tasks. The address is kept so an old
 * link or bookmark lands on sign-in, not on a 404.
 */
export default function RegisterPage(): never {
  redirect("/login");
}
