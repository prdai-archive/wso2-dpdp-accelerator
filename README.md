# dpdp-accelerator
DPDP Accelerator is a collection of artifacts, reference implementations, and documentation that help organizations accelerate the adoption of DPDP Act.

## Build

Requires JDK 11+ (JDK 21+ to run the server), Maven 3.6.3+, and Node.js 20.19+ (or 22.12+) with
npm, all on the `PATH`.

Run from this directory (the repository root) — **not** from `dpdp-accelerator/`,
which only builds the consent portal on its own and skips the accelerator zip:

```sh
mvn clean install
```

This builds the consent portal (frontend + backend WAR) and packages
`wso2-dpdp-is-accelerator-<version>.zip` under
`dpdp-accelerator/accelerators/dpdp-is/target/` — ready to unzip inside
`<IS_HOME>`. See [`docs/docs/setup-guide.md`](docs/docs/setup-guide.md) for
installation.

## Documentation

The `docs/` directory is a [Docusaurus](https://docusaurus.io/) site whose
content lives in `docs/docs/`. Run `npm install` then `npm run start` inside
`docs/` to preview it locally.

- [`docs/docs/setup-guide.md`](docs/docs/setup-guide.md) — installing the accelerator
  and starting the Identity Server.
- [`docs/docs/configuration-guide.md`](docs/docs/configuration-guide.md) — registering
  the consent portal application on a running Identity Server.
- [`docs/docs/event-notification-guide.md`](docs/docs/event-notification-guide.md) —
  creating topics and webhook subscriptions, publishing events, and inspecting
  delivery history.
- [`docs/docs/localization-guide.md`](docs/docs/localization-guide.md) — correcting UI
  wording and localizing Purposes/Elements on a running deployment.
- [`docs/docs/release-guide.md`](docs/docs/release-guide.md) — cutting a release with the
  Release builder workflow.

## Roles

Assign every portal user one of these two roles per tenant (Console →
**User Management → Users → *user* → Roles**):

| Role | Assign to |
|---|---|
| `dpdp-consent-user` | Regular users, to manage their own consents. |
| `dpdp-consent-admin` | Administrators, to manage other people's consents and the purpose/element catalog. |

See [`docs/docs/configuration-guide.md`](docs/docs/configuration-guide.md#4-assign-portal-roles)
for details.
