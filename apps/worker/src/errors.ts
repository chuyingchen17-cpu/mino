export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

export const badRequest = (code: string, message: string) => new AppError(400, code, message);
export const unauthorized = () => new AppError(401, "unauthorized", "Authentication is required");
export const forbidden = (code: string, message: string) => new AppError(403, code, message);
export const notFound = (resource = "resource") => new AppError(404, "not_found", `${resource} was not found`);
export const conflict = (code: string, message: string) => new AppError(409, code, message);
export const upstreamUnavailable = (code: string, message: string) => new AppError(503, code, message);

export function isUniqueConstraintError(error: unknown): boolean {
  return error instanceof Error && /UNIQUE constraint failed|constraint failed/i.test(error.message);
}
