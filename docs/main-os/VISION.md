# mAIn OS — headless OS pro AI agenty

> Vision & brainstorming dokument · v0.1 (draft)
> Datum: 2026-07-04
>
> **mAIn OS** = *main* + *AI*. Operační systém, kde **agent je občan první třídy**, ne
> aplikace přišroubovaná na systém navržený pro lidi. Headless: žádný desktop,
> žádné GUI, žádný člověk u klávesnice. Jen agenti, jejich nástroje, paměť,
> izolace a rozpočty — a řídicí rovina, přes kterou to celé pozoruješ a ovládáš.

---

## 1. Proč vůbec „OS pro agenty"

Dnešní agenti běží na systémech navržených v 90. letech pro *time-sharing mezi
lidmi*. Důsledky, které dnes všichni obcházíme lepidlem:

- **Dlouho běžící VM/kontejnery, které 80 % času zahálí** — nebo serverless s
  2–5 s cold startem. Agentní workload je ale *bursty, efemérní, výpočetně
  špičkový* — přesný opak toho, na co je Linux stavěný.
- **Bezpečnost je bolt-on.** Agent generuje a spouští kód, kterému nevěříš.
  Kontejner není bezpečnostní hranice; potřebuješ microVM/gVisor, ale to si dnes
  každý skládá ručně.
- **LLM tokeny, GPU čas, API rate-limity a $ nejsou plánovatelné zdroje.**
  OS o nich neví. Přitom to jsou *ty* zdroje, které agent spotřebovává.
- **Paměť agenta je ad-hoc.** Vektorové DB, kontextová okna, blackboardy —
  žádná systémová abstrakce, každý framework znovu.
- **Nástroje = nekontrolovaný syscall.** Agent zavolá cokoli, na co dosáhne.
  Chybí capability model, audit, provenance, human-in-the-loop brány.
- **Žádná reprodukovatelnost.** Agent něco udělal ve tři ráno; co přesně a proč,
  se dozvíš jen z logů, které nikdo nenavrhl.

**Teze mAIn OS:** tyhle věci nejsou problém frameworku, ale *problém operačního
systému*. Scheduling, izolace, správa paměti, správa zdrojů, ABI pro nástroje,
identita a audit — to je přesně to, co OS historicky řeší. Jen je potřeba to
navrhnout znovu s agentem, ne člověkem, jako primárním uživatelem.

---

## 2. Krajina — co už existuje (a kam se vejdeme)

| Projekt / vrstva | Co dělá | Vztah k mAIn OS |
|---|---|---|
| **AIOS** (Rutgers, COLM 2025) | „LLM jako kernel, agent jako aplikace". Scheduler, context switch, memory/tool management. 2,1× rychlejší běh díky OS-style dispatchi LLM dotazů. | Nejbližší akademický předchůdce. Bereme *koncept* (LLM-aware scheduler), ale stavíme produkční, bezpečnostně-first substrát pod tím. |
| **Firecracker / Kata / gVisor** | Izolace: microVM s vlastním kernelem (~125 ms boot) / user-space kernel / hardened kontejner. | Naše **izolační vrstva**. Nevymýšlíme — integrujeme a orchestrujeme. |
| **unikernel.ai, Mewz** | Kompilace agenta do unikernelu, boot <50 ms, scale-to-zero, immutable. | Volitelný „fast path" pro důvěryhodné, opakované workloady. |
| **Microsandbox, E2B, Modal, Northflank, Daytona** | Hostované sandboxy pro běh AI kódu, některé s nativním MCP. | Komerční konkurence na *jedné* vrstvě. mAIn OS je celý stack + governance, ne jen sandbox-as-a-service. |
| **MCP (Model Context Protocol)** | De-facto standard pro agent↔nástroj. | Naše **syscall ABI** pro nástroje. |
| **mem0 / OpenMemory** | MCP-kompatibilní paměťové servery, vrstvená paměť. | Referenční implementace naší **paměťové vrstvy**. |

**Kde je díra:** nikdo nedává dohromady *immutable headless substrát + per-task
microVM izolaci + LLM-aware scheduler + tokeny/dolary jako plánovaný zdroj +
capability-based tool bus + provenance/audit* do jednoho koherentního systému s
deklarativní řídicí rovinou. To je pozice mAIn OS.

---

## 3. Architektura (zdola nahoru)

```
┌──────────────────────────────────────────────────────────────┐
│  ŘÍDICÍ ROVINA  — deklarativní manifesty (Agentfile), API,    │
│  observabilita: traces reasoningu, tool-callů, nákladů        │
├──────────────────────────────────────────────────────────────┤
│  IDENTITA & GOVERNANCE — identita agenta (SPIFFE-like),       │
│  capability grants, podepsaná provenance, immutable audit,    │
│  human-in-the-loop brány pro rizikové akce                    │
├──────────────────────────────────────────────────────────────┤
│  TOOL BUS (MCP jako ABI) — capability-scoped nástroje,        │
│  policy engine (seccomp pro nástroje), audit každého callu    │
├──────────────────────────────────────────────────────────────┤
│  PAMĚŤOVÝ SUBSYSTÉM — vrstvená paměť: working / epizodická /   │
│  sémantická / sdílený blackboard; namespaced, verzovaná       │
├──────────────────────────────────────────────────────────────┤
│  AGENT KERNEL („mAInd") — lifecycle agentů, scheduling,       │
│  context switch, batching LLM dotazů, priority, heartbeaty    │
├──────────────────────────────────────────────────────────────┤
│  ROZPOČTY & ZDROJE — tokeny, GPU, $ a rate-limity jako        │
│  first-class kvóty (cgroups pro tokeny); circuit breakery     │
├──────────────────────────────────────────────────────────────┤
│  IZOLAČNÍ VRSTVA — Firecracker microVM / gVisor „agent cell", │
│  efemérní, snapshot/restore <200 ms, scale-to-zero            │
├──────────────────────────────────────────────────────────────┤
│  HOST SUBSTRÁT — minimální immutable Linux (read-only rootfs, │
│  bez shellu/pkg manageru v produkci), atomické updaty,        │
│  measured/attested boot                                       │
└──────────────────────────────────────────────────────────────┘
```

### Vrstva po vrstvě

**1. Host substrát.** Minimální immutable Linux (inspirace Bottlerocket / bootc /
NixOS image). Read-only rootfs, žádný shell ani balíčkovač v produkci → mizí celá
třída útoků a driftu. Atomické A/B updaty s rollbackem. Measured/attested boot pro
důvěru v to, co vlastně běží.

**2. Izolační vrstva — „agent cell".** Každý agent-task dostane efemérní microVM
(Firecracker) nebo gVisor sandbox s vlastním minimálním kernelem, izolovaný od
hosta na úrovni hardwaru (KVM). Snapshot/restore pro cold start pod 200 ms.
Scale-to-zero, když se nic neděje. Egress sítě default-deny.

**3. Agent kernel („mAInd").** Supervisor, který dělá agentům to, co kernel
procesům: zakládá/zabíjí, plánuje, přepíná kontext, hlídá heartbeaty. Klíčová
inovace inspirovaná AIOS: **scheduler ví o LLM dotazech** — batchuje je,
prioritizuje, dispatchuje efektivně (odtud těch 2,1×).

**4. Rozpočty & zdroje.** Radikální kus: **tokeny a dolary jsou plánovatelný
zdroj.** Agent má kvótu (jako cgroup, ale na tokeny/$/GPU-s). Překročení →
throttle nebo kill. Circuit breaker zastaví utrženého agenta dřív, než ti udělá
díru do rozpočtu nebo do produkce.

**5. Paměťový subsystém.** „Filesystem pro agenty." Vrstvy: *working* (kontext v
RAM), *epizodická* (co se stalo, vektorově), *sémantická* (dlouhodobé znalosti),
*sdílený blackboard* (koordinace mezi agenty). Namespaced per-agent, verzované,
MCP-kompatibilní.

**6. Tool bus.** MCP jako univerzální „syscall ABI". Agent nežádá o nástroj přímo
— žádá kernel, policy engine udělí *scoped capability* (jako seccomp, ale pro
nástroje). Každý call jde do audit logu. Least privilege by default.

**7. Identita & governance.** Každý agent má kryptografickou identitu. Least-priv
capabilities, podepsaná provenance každé akce (kdo, čím, proč), immutable audit
trail, human-in-the-loop brány pro akce nad prahem rizika (peníze, mazání,
externí komunikace).

**8. Řídicí rovina.** Deklarativní — popíšeš agenty/flotily manifestem
(`Agentfile`), OS to reconciluje (k8s-style). Observabilita jako jádro:
traces reasoningu, tool-callů, nákladů, ne bolt-on logy.

---

## 4. Design principy

1. **Agent-native, ne human-native.** Žádné dědictví time-sharingu pro lidi.
2. **Efemérní by default, immutable substrát.** Cell vznikne, udělá práci, zmizí.
3. **Všechno je capability.** Least privilege na nástroje, síť, data.
4. **Tokeny a dolary jsou zdroje.** Plánuj je, kvótuj je, hlídej je.
5. **Reprodukovatelnost & replay.** Záznam běhu → deterministické přehrání.
6. **Observabilita a audit jsou jádro.** Ne přílepek, ale primitivum.
7. **Safe by default.** Sandbox, default-deny egress, kill switch, HITL brány.

---

## 5. Výhody (proč to má smysl)

- **Bezpečnost:** skutečná izolační hranice pro nedůvěryhodný AI-generovaný kód a akce.
- **Náklady & efektivita:** scale-to-zero, batching LLM dotazů, konec 80% idle VM.
- **Rychlost:** cold start pod 200 ms přes snapshoty; volitelně unikernel <50 ms.
- **Governance & compliance:** audit, provenance, HITL — killer feature pro enterprise.
- **Multi-agent na úrovni OS:** orchestrace, sdílená paměť a scheduling jako systémová
  služba, ne jako každý framework znovu.
- **Přenositelnost:** `Agentfile` běží stejně na laptopu i ve flotile.

---

## 6. Rizika a otevřené otázky (poctivě)

- **„Nereinventujeme k8s/serverless?"** Největší riziko. Odlišení musí být
  *agent-native scheduling + tokeny jako zdroj + governance*, ne jen „hezčí sandbox".
- **Chicken-and-egg ekosystém.** OS je k ničemu bez agentů pro něj psaných.
  Nutnost: běžet existující MCP/LangChain/… agenty *bez úprav* od dne jedna.
- **„LLM jako kernel" je elegantní, ale křehké.** Nedeterminismus, halucinace ve
  scheduleru. Doporučení: LLM *radí* scheduleru, deterministická logika *rozhoduje*.
- **Sandbox ≠ ochrana před prompt injection.** MicroVM ochrání *hosta*, ale agent
  s legitimně udělenou capability může být sociálně zmanipulován k jejímu zneužití.
  → capability scoping + HITL brány + anomálie detekce, ne jen izolace.
- **Cena microVM-per-task ve velkém.** Nutná hybridní strategie: gVisor/pooling pro
  levné, Firecracker pro rizikové, unikernel pro horké cesty.
- **Rychle se hýbající standardy.** MCP a spol. se mění; ABI musí být verzované.
- **Scope creep.** Pokušení postavit „všechno". MVP musí být brutálně úzké.

---

## 7. Pojmenování komponent (návrh)

| Komponenta | Návrh jména | Poznámka |
|---|---|---|
| Celý systém | **mAIn OS** | main + AI |
| Agent kernel / supervisor | **mAInd** | „mind" |
| Izolovaná jednotka běhu | **cell** | efemérní agent cell |
| Deklarativní manifest | **Agentfile** | jako Dockerfile/manifest |
| Tokenový/$ účet | **budget** / **quota** | plánovaný zdroj |
| Řídicí CLI | **mainctl** | k8s-style |

---

## 8. Strategické rozcestí (co rozhodnout dřív než začneme stavět)

1. **Vrstva ambice:** distro/image (rychlé, pragmatické) × runtime platforma
   (AIOS-like) × celý stack. → *Doporučení: úzký stack okolo jedné killer smyčky
   (bezpečně + levně + auditovaně spustit jednoho agenta), pak růst.*
2. **Host, nebo cloud?** Self-hosted OS image × managed control plane × obojí.
3. **Cílový uživatel:** enterprise (governance) × indie/dev (rychlost, cena) ×
   výzkum (scheduling). → volba určí feature priority.
4. **Open-source jádro × komerční control plane?** (osvědčený model: Firecracker,
   k8s okolo).

---

## 8b. Rozhodnuto (2026-07-04)

- **Rozsah:** úzký stack, jedna smyčka. Nejdřív *jen headless OS základ* — spodní
  vrstvy 1–2 (host substrát + izolace). Agent kernel a výš přijdou později.
- **Cílovka:** zatím žádná konkrétní; cíl je funkční **headless (unix) OS image**.
- **Model:** **self-hosted OS image** — stáhneš a provozuješ, plná kontrola.

→ Ostatní vrstvy (rozpočty, paměť, tool bus, governance) zůstávají ve vizi, ale
mimo aktuální scope. Stavíme podlahu, ne celý dům.

---

## 8c. Phase 0 spec — headless OS image

**Cíl:** minimální, immutable, headless Linux, který nabootuje jako Firecracker
guest (a na baremetalu/VM), nemá nic navíc a je připravený hostit agent cell.

**Co je uvnitř:**
- Minimální kernel (jen KVM guest ovladače, virtio, sítě) — žádné zbytečné moduly.
- init (tini/openrc/systemd-minimal) + jediná systémová služba: **agent supervisor stub**.
- Read-only rootfs, writable jen `tmpfs` + jeden data volume.
- Statická síť (virtio-net), SSH volitelně jen v dev buildu.
- MCP tool proxy stub (placeholder pro pozdější tool bus).

**Co je venku (záměrně):**
- Žádný desktop/GUI, žádný X, žádný audio.
- V produkčním buildu žádný shell ani balíčkovač (dev build je mít smí).
- Žádné multi-user věci, žádný cron pro lidi, žádné login manaery.

**Kandidáti na base (rozcestí #4 — čím image stavíme):**

| Přístup | Plus | Minus |
|---|---|---|
| **NixOS (flake)** | deklarativní, reprodukovatelné, atomické rollbacky — ideál pro immutable OS | strmější křivka, větší build |
| **Buildroot** | nejmenší rootfs, plná kontrola | ruční, pomalá iterace |
| **bootc / Fedora** | OCI-native immutable, atomické updaty | těžší než agent potřebuje |
| **Alpine + mkinitfs** | malé, známé, rychlé | méně „immutable by design" |

*Doporučení: **NixOS flake** — sedí na princip „immutable & reprodukovatelné",
build je jeden `nix build`, iterace deklarativní. Buildroot jako fallback, když
chceme opravdu minimální rootfs.*

**Deliverable Phase 0:** `nix build .#mainos-image` → bootovatelný headless image
+ `mainctl run <cell>` skript, který ho spustí ve Firecrackeru a ukáže život
supervisor stubu.

---

## 9. MVP roadmap

- **Fáze 0 — „jeden agent, bezpečně a viditelně":**
  minimální immutable host image + Firecracker launcher + MCP tool proxy s
  audit logem. *Cíl: spusť libovolného MCP agenta v izolaci a viz každý jeho krok.*
- **Fáze 1 — rozpočty a paměť:**
  token/$ kvóty + circuit breaker + vrstvený paměťový server + snapshot fast-start.
- **Fáze 2 — flotily:**
  deklarativní `Agentfile`, reconcile smyčka, policy/capability engine, blackboard.
- **Fáze 3 — reasoning-aware:**
  LLM-informovaný scheduler (batching à la AIOS), record/replay, attestace.

---

## 10. Zdroje / inspirace

- [AIOS: LLM Agent Operating System (arXiv 2403.16971)](https://arxiv.org/abs/2403.16971) · [GitHub agiresearch/AIOS](https://github.com/agiresearch/AIOS)
- [LiteCUA: Computer as MCP Server (arXiv 2505.18829)](https://arxiv.org/pdf/2505.18829)
- [How to sandbox AI agents in 2026 — MicroVMs, gVisor (Northflank)](https://northflank.com/blog/how-to-sandbox-ai-agents)
- [AI Agent Sandbox: How to Safely Run Autonomous Agents (Firecrawl)](https://www.firecrawl.dev/blog/ai-agent-sandbox)
- [Microsandbox — self-hosted sandboxes booting in 200ms](https://www.blog.brightcoding.dev/2026/06/30/microsandbox-self-hosted-sandboxes-that-boot-in-200ms)
- [gVisor vs Kata vs Firecracker showdown (DEV)](https://dev.to/agentsphere/choosing-a-workspace-for-ai-agents-the-ultimate-showdown-between-gvisor-kata-and-firecracker-b10)
- [Unikernel.ai — unikernel runtime for AI agents](https://www.unikernel.ai/)
- [Mewz — unikernel for Wasm/WASI](https://github.com/mewz-project/mewz)
- [State of AI Agent Memory 2026 (mem0)](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [awesome-agent-runtime-security](https://github.com/bureado/awesome-agent-runtime-security)

---

*Tento dokument je živý draft — brainstorming, ne finální spec. Sekce 8 (rozcestí)
je záměrně otevřená; rozhodnutí tam určí, co z fáze 0 skutečně postavíme.*
