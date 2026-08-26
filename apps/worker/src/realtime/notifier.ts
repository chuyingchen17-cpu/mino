export async function notifyAccounts(env: Env, accountIDs: readonly string[]): Promise<void> {
  const unique = [...new Set(accountIDs)];
  await Promise.allSettled(unique.map(async (accountID) => {
    const id = env.ACCOUNT_REALTIME.idFromName(accountID);
    await env.ACCOUNT_REALTIME.get(id).notify();
  }));
}
