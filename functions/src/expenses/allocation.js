export function allocateExpense(amount, orderedParticipantIds) {
  if (!Number.isSafeInteger(amount) || amount <= 0) {
    throw new TypeError('Expense amount must be a positive safe integer');
  }
  if (!Array.isArray(orderedParticipantIds) || orderedParticipantIds.length === 0) {
    throw new TypeError('At least one participant is required');
  }
  if (orderedParticipantIds.some((id) => typeof id !== 'string' || id.trim() === '') ||
      new Set(orderedParticipantIds).size !== orderedParticipantIds.length) {
    throw new TypeError('Participants must be unique nonempty ids');
  }

  const base = Math.floor(amount / orderedParticipantIds.length);
  const remainder = amount % orderedParticipantIds.length;
  return Object.fromEntries(orderedParticipantIds.map((id, index) => [id, base + (index < remainder ? 1 : 0)]));
}
