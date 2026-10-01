# 36 — Auth edges (pass 3, Phase 8)

Change email, confirm it from the mailed link, reset a password from the
mailed link. `ValidateSession` is deliberately not called: `JWTTokenInspector`
answers "who am I" locally and web only uses it as a race workaround.

## RPCs and links

- `AuthService.ChangeEmail{password, new_email}` → the server mails
  `https://lociai.fyi/auth/confirm-email-change?token=…` to the new address
  (`FRONTEND_URL`, infra `apps/loci/data/config.yaml`).
- `AuthService.ConfirmEmailChange{token}` (token ≥ 16 chars).
- `AuthService.ResetPassword{token, new_password}` from
  `https://lociai.fyi/auth/reset-password?token=…` (token ≥ 32, password ≥ 8).
  `ForgotPassword` was already wired on the login screen.

## Pieces

- `Features/Auth/Model/AuthEdges.swift` — web's rules as pure functions
  (`newPasswordProblem`, `emailChangeProblem`) and request builders that
  return nil when a rule fails, so a rejected form never reaches the server.
- `Features/Settings/UI/ChangeEmailView.swift` — Security › Change email:
  password + new address → "Check your inbox" (the old address keeps working
  until the link is opened).
- `Features/Auth/UI/ResetPasswordView.swift` — new password twice → done →
  Sign in. `ConfirmEmailView` confirms on appear and reports.
- `AppLink.resetPassword(token:)` / `.confirmEmail(token:)` parse the token
  from the query (`/auth/<page>?token=`), on `lociai.fyi` and `loci://auth/…`.
  Both are `isAuthEdge`: signed in they open on the Profile tab like any link;
  signed out `lociApp` takes them off the router and shows them as a sheet
  over the login screen. Web's AASA needs `/auth/*` for the tap to reach the
  app from Mail (plan Phase 9); until then the link opens the web page.
- Analytics: `password_reset`, `email_change_requested`, `email_change_confirmed`.

## Previews

`-designPreview changeEmail | resetPassword | confirmEmail`.
