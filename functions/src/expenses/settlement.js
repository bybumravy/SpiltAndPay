import { allocateExpense } from './allocation.js';

export function aggregateSession(items, members) {
  if (!Array.isArray(items) || !Array.isArray(members)) {
    throw new TypeError('Items and members must be arrays');
  }

  const membersById = new Map();
  for (const member of members) {
    if (!member || typeof member.id !== 'string' || member.id.trim() === '' || membersById.has(member.id)) {
      throw new TypeError('Members must have unique nonempty ids');
    }
    if (member.type !== 'account' && member.type !== 'guest') {
      throw new TypeError(`Unsupported member type for ${member.id}`);
    }
    membersById.set(member.id, member);
  }

  const totalAmount = 0;
  const paidByMember = {};
  const owedByMember = {};
  const guestClaimsByPayer = {};
  const accountNetPositions = {};
  for (const member of members) {
    if (member.type === 'account') accountNetPositions[member.id] = 0;
  }

  let sessionTotal = totalAmount;
  for (const item of items) {
    if (!item || !Number.isSafeInteger(item.amount) || item.amount <= 0) {
      throw new TypeError('Expense amount must be a positive safe integer');
    }
    const payer = membersById.get(item.payerId);
    if (!payer || payer.type !== 'account') {
      throw new TypeError('Expense payer must be an account member');
    }
    const shares = allocateExpense(item.amount, item.participantIds);
    if (item.participantIds.some((id) => !membersById.has(id))) {
      throw new TypeError('Expense participant must be a current member');
    }

    sessionTotal += item.amount;
    paidByMember[payer.id] = (paidByMember[payer.id] ?? 0) + item.amount;
    for (const [memberId, amount] of Object.entries(shares)) {
      owedByMember[memberId] = (owedByMember[memberId] ?? 0) + amount;
      const member = membersById.get(memberId);
      if (member.type === 'guest') {
        guestClaimsByPayer[payer.id] = (guestClaimsByPayer[payer.id] ?? 0) + amount;
      } else {
        accountNetPositions[memberId] -= amount;
      }
    }
    accountNetPositions[payer.id] += item.amount;
  }

  for (const [payerId, amount] of Object.entries(guestClaimsByPayer)) {
    accountNetPositions[payerId] -= amount;
  }
  return { totalAmount: sessionTotal, paidByMember, owedByMember, guestClaimsByPayer, accountNetPositions };
}
