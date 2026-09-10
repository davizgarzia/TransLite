export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }

  toResponse(extraHeaders: Record<string, string> = {}): Response {
    return Response.json(
      { error: { code: this.code, message: this.message } },
      { status: this.status, headers: extraHeaders },
    );
  }
}
