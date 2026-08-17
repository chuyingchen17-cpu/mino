export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string
  ) {
    super(message);
    this.name = "AppError";
  }
}

export const badRequest = (code: string, message: string): AppError =>
  new AppError(400, code, message);

export const unauthorized = (): AppError =>
  new AppError(401, "unauthorized", "A valid bearer token is required");

export const notFound = (resource: string): AppError =>
  new AppError(404, "not_found", `${resource} was not found`);

export const conflict = (code: string, message: string): AppError =>
  new AppError(409, code, message);
