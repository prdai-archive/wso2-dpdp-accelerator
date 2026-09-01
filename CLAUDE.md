# Working in this repo

## What this is

An **accelerator for WSO2 Identity Server 7.3.0** — not a standalone application. The build
produces a zip that is unpacked over an existing IS distribution: OSGi bundles into
`repository/components/dropins`, a WAR into `repository/deployment/server/webapps`, and a
complete `deployment.toml` that replaces the product's own. Nothing here runs on its own; almost
everything needs a live IS to exercise.

The rest of this file is conventions that have emerged across the codebase — follow them when
adding a feature, a module, or a config option, since they're not written down anywhere else yet.

## Build

Requires JDK 11+ (JDK 21+ to run the server), Maven 3.6.3+, Node.js 20.19+/22.12+ with npm.

```sh
mvn clean install                    # from the REPOSITORY ROOT
```

Run from the repository root, **not** from `dpdp-accelerator/`. The root pom aggregates
`dpdp-accelerator` *and* `dpdp-accelerator/accelerators` separately (the accelerators subtree
parents to the root pom, matching the Financial Services accelerator layout), so building from
`dpdp-accelerator/` silently skips the accelerator zip and only builds the portal. See
[`README.md`](README.md) for more background on prerequisites.

Output: `dpdp-accelerator/accelerators/dpdp-is/target/wso2-dpdpiam-accelerator-<version>.zip`

### Tests

| Scope | Command |
| --- | --- |
| Java (TestNG via surefire, suite defined in `src/test/resources/testng.xml`) | `mvn test` |
| Single Java test class | `mvn test -pl dpdp-accelerator/components/org.wso2.dpdp.accelerator.identity.extensions -Dtest=DPDPConsentPortalAppProvisioningUtilTest` |
| Frontend (Vitest) | `cd dpdp-accelerator/react-apps/consent-portal/frontend && npm test` |
| Single frontend test | `npm test -- src/__tests__/SomeThing.test.tsx` |
| Frontend lint / format | `npm run lint` / `npm run format:check` |
| E2E (Playwright, needs a deployed IS) | `cd dpdp-integration-test-suite && ./run-e2e.sh [tests/03-consents]` |

CI runs the Java/frontend build and the full E2E suite on every PR to `main` and `dev` via
`.github/workflows/pr-checks.yml`, which deploys a fresh IS 7.3.0 from scratch. It needs no
secrets. Role *membership* is the one thing the accelerator never provisions, so both CI and a
fresh local install get their accounts from
`dpdp-integration-test-suite/scripts/provision-test-users.sh` (idempotent).

**Use npm, not pnpm.** `package-lock.json` is the committed lockfile and the Maven build invokes
`npm install` / `npm run build`. The frontend `README.md` and `AGENTS.md` both say pnpm — they are
stale on this point; don't follow them for package management even though they're otherwise the
canonical frontend policy (see [Frontend conventions](#frontend-conventions) below).

`npm run build` is not just Vite: it chains `tsc -b`, then `security:verify`, `i18n:verify`, and
`generate:shell`. Any of those four can fail the Maven build.

## Architecture

### Deployment pipeline

```
frontend/ (Vite SPA)
  └─ npm run build → frontend/dist (incl. generated index.jsp/home.jsp/auth.jsp)
      └─ consent-portal.war  (war plugin, webResources = frontend/dist, webXml = ./web.xml)
          └─ unzipped by accelerators/dpdp-is antrun `create-solution` into carbon-home/
              └─ wso2-dpdpiam-accelerator-<version>.zip
                  ├─ bin/merge.sh <IS_HOME>      copies carbon-home/* over the product
                  └─ bin/configure.sh <IS_HOME>  installs deployment.toml, runs consent DB migration
```

`merge.sh` deliberately deletes every previously-deployed accelerator webapp (exploded directory
and `.war`) and any `org.wso2.dpdp.accelerator.*` jar in dropins before copying fresh ones in — a
stale file left over from an older accelerator version would otherwise sit alongside the new one
indefinitely, since `cp -r` only adds/overwrites and never deletes. See
[Build-artifact hygiene vs. stateful data](#build-artifact-hygiene-vs-stateful-data) for the
general principle this follows.

Adding a new internal webapp requires two edits, not one: a `<module>` in
`dpdp-accelerator/pom.xml` (there is no aggregator pom under `internal-webapps/`) **and** an
`<unzip>` in the `create-solution` antrun execution of `accelerators/dpdp-is/pom.xml`. See
`components/README.md` and `internal-webapps/README.md`.

### What lives where

- **`components/org.wso2.dpdp.accelerator.common`** — shared, feature-agnostic plumbing: the
  `dpdp-accelerator.xml` config parser/service, the JDBC persistence manager
  (`JDBCPersistenceManager` + `DBUtils` — names deliberately match the WSO2 Open Banking
  accelerator's `JDBCPersistenceManager`/`DatabaseUtil`), a shared outbound-HTTP client factory
  (`HTTPClientUtils`), common constants and exceptions. Nothing feature-specific belongs here —
  and the inverse holds too: if a utility in a feature module (`event.notifications.common`,
  etc.) turns out to have zero feature-specific logic, move it here rather than let a second
  feature reinvent it later. The reverse mistake is just as real, though — don't move something
  here just because it's *theoretically* generic if it only has one consumer today (e.g.
  `HmacSigner` stayed in `event.notifications.common`); moving code preemptively without a
  second real consumer just adds indirection.
- **`components/org.wso2.dpdp.accelerator.identity.extensions`** — the actual WSO2 IS extension
  *points*: `TenantMgtListener` hooks, OSGi service registrations, application/role
  provisioning. This is where you plug into IS's own lifecycle (tenant create/update, consent
  status-change hooks, etc.), not where feature business logic lives. See
  [Tenant auto-provisioning](#tenant-auto-provisioning) below.
- **`components/org.wso2.dpdp.accelerator.consent.extensions`** — the DAO/service layer for
  consent-related extensions. Currently holds consent status-audit/history capture and read
  (`ConsentHistoryDAO`, `ConsentHistoryService`); named generically so a future, unrelated
  consent extension can live here too instead of forcing another rename.
- **`internal-webapps/org.wso2.dpdp.accelerator.consent.mgt.extensions.endpoint`** — the REST
  layer exposing `consent.extensions`' data over HTTP (JAX-RS/CXF WAR). Business logic stays in
  the `consent.extensions` service layer; this module only orchestrates request/response
  shaping, auth-adjacent checks it owns (e.g. ownership), and DTO mapping.
- **`react-apps/consent-portal`** — the end-user-facing SPA (see
  [Consent portal frontend](#consent-portal-frontend-react-appsconsent-portal) below). Talks to
  IS's own APIs directly; does not go through the `internal-webapps` endpoint.
- **`accelerators/dpdp-is/`** — packages every module above into `carbon-home/`, assembles the
  distributable zip, and ships `bin/merge.sh` + `bin/configure.sh` for installing over an
  `IS_HOME`.

Registering a new module: add it to `dpdp-accelerator/pom.xml`'s `<modules>`, and copy its built
artifact into the distribution via the antrun `create-solution` execution in
`accelerators/dpdp-is/pom.xml`. See `components/README.md` and `internal-webapps/README.md`.

### `deployment.toml` is replaced, not merged

`accelerators/dpdp-is/repository/resources/wso2is-7.3.0-deployment.toml` is the **complete** stock
IS 7.3.0 file, byte-for-byte, with three placeholders (`IS_HOSTNAME`, `IS_ADMIN_USERNAME`,
`IS_ADMIN_PASSWORD`) that `configure.sh` substitutes, plus the accelerator's settings appended
under a banner. Keep the banner boundary honest: anything above it must stay identical to stock so
the diff against a fresh pack remains reviewable. `configure.sh` backs the operator's file up to
`deployment.toml.bak-<timestamp>`.

Supporting a new IS version means adding a template beside this one and pointing
`PRODUCT_CONF_PATH` (in `repository/conf/configure.properties`) at it.

`[consent_mgt] enable_v2_api = true` is the load-bearing switch: it re-renders
`repository/conf/identity/resource-access-control-v2.xml` and registers the v2 API resources with
their `internal_consent_mgt_*` scopes. Do not hand-edit those generated files.

### Tenant auto-provisioning

`DPDPIdentityExtensionTenantMgtListener` creates the `DPDP_CONSENT_PORTAL` application and the
`dpdp-consent-user` / `dpdp-consent-admin` roles on tenant create/update, mirroring how IS
provisions Console and My Account. Controlled by `[dpdp_accelerator.consent_portal]` in
`deployment.toml`; `client_id` there must match what the deployed portal expects or sign-in breaks.
Role *membership* is never provisioned — it is assigned by hand in the Console. See
[Provisioning/listener idempotency](#provisioninglistener-idempotency) for the update-path rule
this and every other tenant lifecycle hook follows.

`org.wso2.dpdp.accelerator.common` holds the `deployment.toml` config parser
(`DPDPConfigParser`) exposed as an OSGi service; `identity.extensions` consumes it.

### Integration test suite

Runs against a **real, persistent, shared** IS — nothing is mocked, and the environment never
resets. Consequences that shape every test: assert by unique marker or server-issued ID, never by
empty lists or row counts. Personas log in **once per run**, cached across workers in
`fixtures/auth.fixtures.ts`. Tests delete Elements/Purposes they create but not Consents — the
product has no delete-by-id for them, so they accumulate.

**Before writing or changing a test there, read `dpdp-integration-test-suite/AGENTS.md`.** It
carries the rules that aren't guessable: the crossed directory/test-ID numbering, sourcing locators
from the frontend's i18n rather than from memory, the leading-slash `goto()` trap, the two
load-bearing lines in `pageForPersonaState`, and the measured flake profile.

## Naming standards

- A module's Java package root matches its Maven artifactId exactly
  (`org.wso2.dpdp.accelerator.<name>`).
- Prefer a generic module name over a narrow one if more than one related feature could
  plausibly live in the same module later (e.g. `consent.extensions`, not `consent.history` —
  history capture/read is the first thing in it, not the only thing it's for).
- Class suffixes are meaningful and consistent — match the existing one for what you're adding:
  `*DAO`/`*DAOImpl` (persistence), `*Service`/`*ServiceImpl` (business logic), `*Constants`,
  `*Component` (OSGi `@Activate`/`@Deactivate`), `*DataHolder` (OSGi service holder singleton),
  `*Exception`, `*Util`, `*Record`/`*Model` (DAO-layer POJOs), `*Listener` (Carbon/IS lifecycle
  hooks), `*Api` (JAX-RS resource classes), `*DTO` (REST payloads — generated, see below).
- REST error codes follow `<MODULE-PREFIX>-000NN` (e.g. `CH-00001` for the consent-history
  endpoint) in a dedicated `*ErrorCodes` constants class — one class, one prefix, per webapp.
  A webapp's own transport/mapper-level codes (malformed JSON, framework exceptions — errors
  that never reach the service layer) are a *different* code space from the service layer's own
  domain error codes (e.g. `EventNotificationServiceConstants`'s `EN-4xxx`/`EN-5xxx`), even when
  they share a letter prefix by coincidence. Keep the two visually distinguishable (e.g.
  different digit counts, like `EN-00001` vs `EN-4001`) — a bare numeric rename can otherwise
  silently collide two unrelated error conditions onto the same code.
- IS role names are lowercase-hyphenated and scoped to what they're for, e.g.
  `dpdp-consent-admin` / `dpdp-consent-user`.

## Config: adding a new setting

`dpdp-accelerator.xml` config lives entirely in the `common` module. Adding a new setting means
touching this chain, in order:

1. Add the dot-joined XML-path key as a constant in `DPDPCommonConstants` (e.g.
   `"ConsentHistory.SnapshotEnabled"`), plus a `DEFAULT_*` constant if it needs one.
2. Add a typed getter in `DPDPConfigParser` using the existing
   `getConfigurationAsString(KEY).map(...).orElse(default)` pattern — never read the raw map
   directly from outside the parser.
3. Add the matching getter to the `DPDPConfigurationService` interface and delegate to it from
   `DPDPConfigurationServiceImpl`. Other bundles must consume config via this OSGi service
   (`@Reference`/`getOSGiService`), never via `DPDPConfigParser.getInstance()` directly, except
   inside the `common` module itself.
4. Add the element to
   `accelerators/dpdp-is/carbon-home/repository/resources/conf/templates/repository/conf/dpdp-accelerator.xml.j2`,
   with a Jinja `{% if %}`/`{% else %}` default matching step 1's default.
5. Add the corresponding TOML key under a `[dpdp_accelerator.<feature>]` table in
   `accelerators/dpdp-is/repository/resources/wso2is-7.3.0-deployment.toml`, documented with a
   comment explaining what it controls. This file is otherwise a byte-for-byte copy of stock IS
   config appended under a banner — see [`deployment.toml` is replaced, not merged](#deploymenttoml-is-replaced-not-merged).
6. If the value can be a secret, do nothing extra — any element already supports
   `svns:secretAlias="..."` and `DPDPConfigParser` resolves it transparently via Secure Vault.

## Logging

- Use Apache Commons Logging exclusively — `org.apache.commons.logging.Log`/`LogFactory`, not
  SLF4J or a direct log4j import. Declare it as
  `private static final Log LOG = LogFactory.getLog(<ClassName>.class);`.
- Any user- or request-supplied string (tenant domain, consent ID, path/query param) must be
  passed through `org.wso2.dpdp.accelerator.common.util.LogSanitizer.sanitize()` before it goes
  into a log message, to block log injection via embedded `\r`/`\n`. A few older classes still
  carry their own private `sanitize()` copy predating this shared utility — don't add new ones;
  use `LogSanitizer` for anything new.
- Level conventions:
    - `LOG.debug` — routine/expected activity: OSGi activate/deactivate, successful writes,
      benign "not found" cases that produce a normal 404 rather than an operator-relevant failure.
    - `LOG.error` — always paired with the caught exception, for genuine unexpected failures,
      immediately before translating it into an API-level exception (e.g. 500).
    - `LOG.info` — reserved for one-time, operationally significant events only (e.g. "provisioned
      the consent portal for tenant X"), not routine per-request activity.
    - `LOG.warn` is not used in this codebase — pick `debug` or `error` based on whether the
      situation is expected.
- When a log statement is wrapped in an `isXEnabled()` guard, the guard's level must match the
  log call's own level exactly (`if (LOG.isDebugEnabled()) { LOG.debug(...); }`, never
  `isInfoEnabled()` guarding a `.debug(...)` call or vice versa). This drifts easily when a log
  call gets reclassified to a different level without updating its guard, and the mismatch is
  easy to miss by eye — grep for `isXEnabled()` and check the line right after it whenever you
  touch log levels.
- Never log tokens, emails, or other PII — this applies to the frontend too, not just the Java
  bundles.

## Consent portal frontend (`react-apps/consent-portal`)

- It's a client-side-routed SPA (`react-router-dom`, Vite build), not server-rendered — routes
  like `/dashboard`, `/consents`, `/purposes` all resolve client-side. The Vite build output
  (`dist/`) gets wrapped into `index.jsp`/`home.jsp`/`auth.jsp` shells for the auth handoff, then
  packaged as `consent-portal.war` and deployed into `carbon-home`.
- It talks **directly to WSO2 IS's own APIs** — not through our `internal-webapps` endpoint:
    - `/api/identity/consent-mgt/v2.0` — IS-native consent-mgt v2 (purposes/elements catalog,
      admin consent listing).
    - `/api/users/v1/me/consents` — IS-native self-service consent actions (authorize/revoke).
    - The accelerator's own `/api/dpdp/consent-mgt/v1` (status-audit/history reads) is **not
      currently wired into the frontend** — it exists as a backend-only API. Wiring it in is
      outstanding work, not something already done.
- **Auth is a public OIDC client (auth-code + PKCE) against the Identity Server itself — there is
  no backend-for-frontend of our own.** An earlier design had one with split-cookie tokens; it was
  removed. Tokens live in the `@asgardeo/auth-spa` web worker, never in page script — every API
  call routes through `httpRequest` in `src/utils/authClient.ts` so the worker attaches the token.
- The authorization code itself never reaches page script either: it's parked server-side in the
  HTTP session via the JSP shell. Three generated JSPs handle the handoff (`web.xml` documents the
  chain): `index.jsp` forwards an incoming code to `/authenticate`, `home.jsp` parks it in the HTTP
  session, `auth.jsp` hands it over once and clears it so a reload can't replay it.
- No build-time base URL: `VITE_API_BASE_URL` is empty on purpose — every request is same-origin
  and tenant-qualified, with the base path derived from `window.location` at runtime via
  `src/utils/basePath.ts` (so the same build works unqualified at `/consent-portal` and
  tenant-qualified at `/t/<tenant>/consent-portal`). Use those helpers rather than constructing
  URLs yourself — `tenantFromPath` deliberately constrains the tenant charset because it gets
  spliced into request URLs. Don't hardcode a host or tenant path into new frontend code.
- `deployment.config.json`, fetched at runtime (not compiled into the bundle), supplies the
  OAuth `clientID` and scope list — this is how the same build adapts to whatever
  `[dpdp_accelerator.consent_portal] client_id` is set to per install. `authClient.ts` keeps a
  hardcoded fallback copy of those same defaults — **change both or they drift.**
- `web.xml` maps the SPA shell to `/*`, so every static path the build emits at the webapp root
  needs its own explicit `default` servlet mapping, or it silently gets served the shell's HTML
  instead of the real asset. `/i18n/*` is mapped for exactly this reason — follow the same pattern
  for any new top-level static path.
- i18n covers English plus the 22 languages of the Eighth Schedule. Translations are fetched at
  runtime from `public/i18n/<lang>/`, **not bundled**. New keys go in `public/i18n/en/common.json`
  and must be mirrored into every other language (an English placeholder value is fine there —
  translation is a separate pass); `npm run i18n:verify` and `src/__tests__/I18nKeys.test.ts`
  enforce completeness and will fail the build otherwise. `catalog.json` is exempt: it holds
  wording for admin-created Purposes/Elements and is allowed to be incomplete.

## Frontend conventions

`dpdp-accelerator/react-apps/consent-portal/frontend/AGENTS.md` is the canonical coding-style
policy (with `.ai/oxygen-ui/AGENTS.md` for component specifics) — **except its package-manager
guidance, which is stale; see [Use npm, not pnpm](#build) above.** The rules that bite most often:

- Import UI from `@wso2/oxygen-ui` only, never `@mui/material`. Style with `sx` + theme tokens, no
  hardcoded colors/spacing.
- No `any`; explicit return types; interfaces for object shapes. Do not disable ESLint rules.
- Keep code under `src/{components,features,hooks,types,utils,__tests__}`. Components
  `PascalCase.tsx` with a default export, logic `camelCase.ts`, folders `kebab-case`.
- API access belongs in modules/hooks (`src/utils/apiClient.ts` + TanStack Query), not in
  presentational components.
- No hardcoded user-facing copy — externalize to i18n keys and use `useTranslation('common')`.

## Adding a new REST API endpoint

Follow the pattern in `consent.mgt.extensions.endpoint`, which itself follows how the Open
Banking accelerator wires its internal webapps:

- Package layout inside the webapp module: `api` (JAX-RS resource classes), `dto` (generated,
  see below), `error` (error-code constants + `ExceptionMapper`), `exception` (a single
  exception type carrying an HTTP status + error code), `util` (pure, unit-testable
  request/response-shaping logic — keep resource classes themselves thin).
- Register resource classes and providers explicitly in `web.xml`'s `CXFNonSpringJaxrsServlet`
  init-params (`jaxrs.serviceClasses`, `jaxrs.providers`) — don't rely on `@Provider`
  annotation-scanning; that's not how the product's own webapps are wired.
- CXF, the JAX-RS API, and Jackson are **not** bundled into `WEB-INF/lib` — they come from
  `<IS_HOME>/lib/runtimes/cxf3/` via `META-INF/webapp-classloading.xml`'s `CXF3,Carbon`
  environment. Any dependency that *is* missing from that directory (checked, not assumed —
  `find $IS_HOME/lib/runtimes/cxf3 -iname '*whatever*'`) needs `compile` scope so it ships in
  `WEB-INF/lib` instead; version-pin it in the root pom against that directory's actual jar.
- Authentication and scope enforcement happen entirely outside this code, via
  `[[resource.access_control]]` entries in `deployment.toml` keyed on the webapp's context path
  — no auth filter/interceptor is declared in the webapp itself. Any ownership check that can't
  be expressed as a scope (e.g. "does this user own this specific consent") is enforced in the
  resource class itself, not left to IS's valve.
- Errors: throw the module's dedicated exception type carrying an HTTP status and one of its
  `*ErrorCodes` constants; a single `ExceptionMapper` (registered in `web.xml`, not `@Provider`)
  converts it to a JSON `ErrorDTO`. Anything uncaught becomes a generic 500 — never let an
  internal exception detail leak into the response.
- A repeated literal used inside a JAX-RS annotation (`@DefaultValue("20")`, `@HeaderParam(
  "group-id")`) can't reference an `int`/generic constant — the annotation attribute needs a
  compile-time constant `String` expression. If the same literal is already a typed constant
  elsewhere (e.g. `EventNotificationCommonConstants.DEFAULT_LIMIT` as an `int`), add a matching
  `String` sibling (`DEFAULT_LIMIT_STR`) specifically for annotation use, with a comment noting
  it must stay in sync with the typed one, rather than leaving the literal duplicated in each
  resource class.

## Generated DTOs

REST response DTOs are generated from an OpenAPI spec (`openapi-generator-maven-plugin`,
generator `jaxrs-cxf`, `generateApis=false` — only models are generated, hand-written resource
classes are never touched by codegen). Generation is off by default behind a skip property;
flip it, review the diff, flip it back, and commit the generated sources under `src/gen/java`
(added as a source root via `build-helper-maven-plugin`, not `target/generated-sources`). The
spec itself should describe the real, full API (paths, params, responses) for genuine
documentation value, even though only the schemas get generated into code.

## OSGi bundle packaging

Every `components/*` module is `<packaging>bundle</packaging>` via `maven-bundle-plugin`. The
instructions block follows one shape — copy it rather than reinventing:

- `Bundle-SymbolicName` is always `${project.artifactId}`.
- `Private-Package` lists implementation packages (`.internal`, `.*.impl`, `.*.constants`,
  `.*.queries`) — never exported.
- `Export-Package` lists the public API surface (models, service interfaces, exceptions) other
  bundles are allowed to depend on, each pinned `;version="${project.version}"`.
- `Import-Package` explicitly names every external package this bundle actually uses, each
  pinned to a version/range property (`;version="${some.version.range}"`), then ends with a
  bare `*` so anything not explicitly listed still resolves rather than failing the build.
- `<_dsannotations>*</_dsannotations>` is required for `@Component`/`@Activate`/`@Deactivate`
  declarative-services annotations to actually get processed into OSGi service descriptors.

## Testing and coverage

See [Tests](#tests) above for the literal commands. Conventions beyond that:

- TestNG (not JUnit) + Mockito. Test classes are registered by package in a per-module
  `src/test/resources/testng.xml` (`<packages><package name="...impl"/></packages>`) — a new
  test package must be added there or it silently never runs.
- Mocking pattern: `@Mock` fields + `MockitoAnnotations.openMocks(this)` in a `@BeforeMethod`,
  not manual `Mockito.mock()` calls scattered through test methods (manual `mock()` is fine
  inline for a one-off collaborator, e.g. a `Connection` supplier lambda).
- Jacoco's `INSTRUCTION` `COVEREDRATIO` minimum is `0.8` for every module. Exclude a class from
  coverage only when it genuinely can't be unit tested (needs a live
  `PrivilegedCarbonContext`, JNDI `InitialContext`, or OSGi-injected service) — put a one-line
  comment on the exclude saying why. Standard always-excluded patterns: `*Constants`,
  `*Component`, `*DataHolder`.
- A brand-new module starts with zero tests and therefore zero coverage — `mvn verify` will fail
  immediately at `0.8` before a single test exists. Add the `jacoco-maven-plugin` block with a
  low interim minimum (e.g. `0.1`, with a one-line comment saying it's interim and should rise as
  more tests land) as soon as the module gets its first real tests, then raise the threshold in a
  later pass once coverage actually grows — don't leave a new module with no jacoco block at all,
  and don't gate it at `0.8` before it has the tests to reach that.
- DAO tests should exercise real SQL, not just mocks: copy the module's real
  `dbscripts/<feature>/h2.sql` into `src/test/resources/h2.sql` as a test fixture, open an
  in-memory H2 connection (`jdbc:h2:mem:<name>;DB_CLOSE_ON_EXIT=FALSE`), and apply the schema with
  `org.h2.tools.RunScript.execute(conn, reader)` in a `@BeforeMethod`. This mirrors the WSO2 Open
  Banking accelerator's own test-fixture convention (a `src/test/resources/dbScripts/` copy,
  distinct from the real production dbscripts) and catches real SQL mistakes that a mocked
  `ResultSet` never would.
- A logging-level fix (see the `isXEnabled()` guard note above) can retroactively drop a
  *different* module's coverage below its own `0.8` gate: if a debug-only log line was only ever
  "accidentally" covered because its guard was wrong (e.g. `isInfoEnabled()`, which is usually
  true by default, guarding a `.debug(...)` call), correcting the guard to `isDebugEnabled()`
  (usually false by default in tests) makes that line stop executing during tests, and its
  instructions become newly "missed." Re-run `mvn clean verify` across the whole reactor after
  any logging-level fix, not just the module you touched — if a class's guarded log line
  genuinely needs coverage, raise the test's logger level explicitly (e.g.
  `java.util.logging.Logger.getLogger(TheClass.class.getName()).setLevel(Level.FINE)` in a
  `@BeforeClass`) rather than loosening the jacoco threshold.

## Dependency and plugin versions

All versions are declared exactly once, in the root `pom.xml`'s `<dependencyManagement>` /
`<pluginManagement>`, as version properties. A module's own `pom.xml` declares a dependency with
only `<groupId>`/`<artifactId>` — never repeat a `<version>`. Add `<scope>` in the module only
when it needs to differ from what's managed (e.g. a dependency is `compile` scope in one
consumer and `provided` in another); otherwise scope is managed too.

When adding a new internal `org.wso2.dpdp.accelerator.*` module, add it to the root pom's
`dependencyManagement` in the same change. A missing entry forces every consumer to inline
`<version>${project.version}</version>` itself — easy to miss in review, and it's exactly how the
complaint modules drifted from this rule.

A property accidentally declared twice in the root pom's `<properties>` block fails silently —
Maven takes the later value with no warning or error. After editing that block, verify with
`mvn -o help:evaluate -Dexpression=<name> -q -DforceStdout` rather than trusting the file by eye.

## OSGi service lifecycle

A manual `bundleContext.registerService(...)` call is not automatically unregistered when the
component deactivates and reactivates — only a full bundle stop does that. Track the returned
`ServiceRegistration` in a field and call `.unregister()` in `@Deactivate`, or a reactivation
leaves a duplicate registration behind. Declarative `@Component(service = ...)` doesn't need this.

## Provisioning/listener idempotency

Tenant lifecycle listeners fire on both create and update. Treat the update path as the recovery
path: check whether something already exists before creating it, never assume a clean slate.
Every provisioning step should be safe to call repeatedly. See
[Tenant auto-provisioning](#tenant-auto-provisioning) for the concrete listener this applies to.

## Build-artifact hygiene vs. stateful data

The real deployment workflow is "rebuild the accelerator, merge it over an already-running
`IS_HOME`," repeated many times — not a one-shot fresh install. Because of that:

- Stale build outputs (dropins jars, exploded webapps) must never linger across a rebuild.
  `maven-clean-plugin` wipes the webapp/dropins overlay at the `initialize` phase before
  repackaging; `merge.sh` removes every stale accelerator webapp and dropins jar from the *live*
  `IS_HOME` before copying fresh ones in — see [Deployment pipeline](#deployment-pipeline).
- Stateful data (database files) must **never** get the same blind-overwrite treatment — that
  would silently delete real data on every merge. Schema setup stays script-driven and
  idempotent (`CREATE TABLE IF NOT EXISTS`), not a file that gets replaced wholesale.

## Database scripts

DDL lives at `accelerators/dpdp-is/carbon-home/dbscripts/<feature>/{h2,mysql}.sql` (one directory
per feature, not per module) and is packaged into the shipped zip automatically since
`carbon-home/` is included wholesale by the assembly descriptor — no separate wiring needed.
Unlike the product's own bundled databases (which get a pre-built, pre-populated file baked in
at WSO2's own build time), a new accelerator-owned database has no such build pipeline: its
schema gets created at install time by `bin/configure.sh`, which runs the `.sql` file with H2's
`org.h2.tools.RunScript` using the H2 engine jar already shipped in
`<IS_HOME>/repository/components/plugins/`. Register the new datasource in `deployment.toml`
using the product's own named-table form (`[datasource.Name]`, matching
`[datasource.AgentIdentity]`), not the `[[datasource]]` array form.

## DAO layer conventions

- Result-set column names read via `rs.getString(...)`/`rs.getInt(...)` etc. go through a
  dedicated per-module column-name constants class (e.g. `EventNotificationDBColumns`), not
  raw string literals repeated across every `*DAOImpl`. The SQL text itself (in `queries/*.java`)
  still spells the column name directly — these constants only cover the Java-side read, so a
  rename still means touching both, just without N copies of the literal on the Java side.
- Status/mode string literals (`'active'`, `'pending'`, `'webhook'`, etc.) must never appear as
  bare literals in Java code or in SQL text built via string concatenation — always go through
  the corresponding enum's `.getValue()` (e.g. `SubscriptionStatus.ACTIVE.getValue()`), even when
  building a literal SQL fragment like `"STATUS = '" + SubscriptionStatus.ACTIVE.getValue() +
  "'"`. This is the only way a status-value rename gets caught by the compiler.
- Every DB table with a dynamic search/list query gets its own `*QueryBuilder` class in
  `dao/queries/` (`TopicQueryBuilder`, `EventQueryBuilder`, `SubscriptionQueryBuilder`) — don't
  hand-build `WHERE`/pagination SQL with a raw `StringBuilder` directly inside the DAO impl, even
  for a "simple" table; the query builder pattern is what makes filters testable independent of
  a live DB. Shared helpers used across builders (`QueryResult`, `escapeLikePattern`) are defined
  once in the `queries` package and reused — never copy-pasted per builder.
- When a public method has both a `(Connection conn, ...)` overload and a convenience
  no-`Connection` overload that opens its own connection, any code that already holds an open
  `Connection` must call the `Connection`-accepting overload, never the convenience one — calling
  the convenience overload from inside an already-open connection silently opens a second,
  redundant connection per call.

## Config conventions

- When there's a stock WSO2 IS precedent for a config shape, mirror it exactly rather than
  inventing a new shape.
- Secrets go through Secure Vault (`svns:secretAlias="..."` on the element, resolved via
  `SecretResolverFactory`), never plaintext in `dpdp-accelerator.xml`.

## When unsure, check precedent

This accelerator follows the WSO2 Financial Services / Open Banking accelerator's patterns
wherever one exists (dropins cleanup, Secure Vault support, datasource config shape, OpenAPI
codegen setup, internal-webapp wiring, root-pom aggregation layout). If a design question comes
up, check how that project solved it before inventing something new.

## Reference docs

`docs/setup-guide.md` (install + start the server), `docs/configuration-guide.md` (portal
application, roles), `docs/localization-guide.md` (fixing wording and localizing Purposes/Elements
on a live deployment without a rebuild).

## Working with an AI agent on this repo

- Never commit or push without being explicitly asked, even after a large multi-file change.
- Keep comments short and explain *why*, not *what* — this repo trims verbose javadoc on sight.
