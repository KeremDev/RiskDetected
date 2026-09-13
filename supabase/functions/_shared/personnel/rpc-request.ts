import { preparePersonnelDirectory } from './directory-request.ts';

/** Only allow the checked, versioned RPCs. Actor/session never come from input. */
export function preparePersonnelRPC(input: unknown) {
  const request = preparePersonnelDirectory(input);
  if (!request) return null;
  if (request.kind === 'read') return {
    functionName: 'isg_personnel_read_v1' as const,
    companyID: request.companyID,
    args: request.args,
  };
  return {
    functionName: 'isg_personnel_mutate_v1' as const,
    companyID: request.companyID,
    operationID: request.operationID,
    args: request.kind === 'create' ? {
      ...request.args, p_action: 'create', p_employee: null,
      p_expected: 0, p_change_department: true,
    } : request.args,
  };
}
