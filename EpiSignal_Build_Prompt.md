# EpiSignal — Complete Build Prompt
## Full-Stack AI Agent: Cell Signaling × Chromatin Biology Hypothesis Engine

---

# PART 1 — WHAT YOU ARE BUILDING

Build EpiSignal: a full-stack, production-grade web application that functions as an AI-powered hypothesis generation agent for researchers in cell signaling and chromatin/epigenetic biology. This is not a chatbot wrapper. It is a purpose-built scientific reasoning tool with a distinctive UI, live database traversal, real-time literature search, and structured hypothesis output. Build everything end to end — landing page, agent interface, backend API, database integrations, and citation system.

---

# PART 2 — FULL ARCHITECTURE

## 2.1 Tech Stack

**Frontend:** React (Vite), TailwindCSS, Framer Motion for animations
**Backend:** Node.js + Express REST API
**AI Layer:** Anthropic Claude API (claude-sonnet-4-20250514, max_tokens: 4096)
**Search Layer:** Exa API (semantic literature search across bioRxiv, PubMed, Cell, Nature, Science)
**Database Traversal:** Direct REST API calls to all organism and protein databases listed below
**Deployment:** Single deployable repo. Frontend served from /client, backend from /server.

## 2.2 External APIs and MCPs Required

### AI
- Anthropic Claude API — claude-sonnet-4-20250514
  Endpoint: https://api.anthropic.com/v1/messages
  Used for: all reasoning, hypothesis generation, cross-organism logic, field mapping

### Literature Search
- Exa API (https://exa.ai)
  Used for: semantic search across bioRxiv, PubMed, Cell Press, Nature, Science, eLife
  Queries fired automatically before every reasoning response
  Returns: title, authors, year, abstract, DOI, direct URL
  All citations returned to user with full attribution

- PubMed E-utilities (free, no key required)
  Endpoint: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/
  Used for: PubMed ID lookup, abstract retrieval, MeSH term traversal

- bioRxiv/medRxiv API (free)
  Endpoint: https://api.biorxiv.org/
  Used for: preprint retrieval for cutting-edge findings not yet in journals

### Protein Databases
- UniProt REST API (free)
  Endpoint: https://rest.uniprot.org/uniprotkb/
  Used for: protein function, PTM sites, domain architecture, organism orthologs, interactions

- PhosphoSitePlus API (requires academic registration)
  Endpoint: https://www.phosphosite.org/
  Used for: kinase-substrate relationships, phosphorylation sites, modification cross-talk

- STRING API (free)
  Endpoint: https://string-db.org/api/
  Used for: protein-protein interaction networks, functional enrichment

- InterPro API (free)
  Endpoint: https://www.ebi.ac.uk/interpro/api/
  Used for: domain architecture, structural family membership, homolog identification across kingdoms

### Gene and Chromatin Databases
- NCBI Gene API (free)
  Endpoint: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/
  Used for: gene function, expression data, orthologs, associated pathways

- Ensembl REST API (free)
  Endpoint: https://rest.ensembl.org/
  Used for: cross-species gene comparison, genomic context, regulatory features

- ENCODE API (free)
  Endpoint: https://www.encodeproject.org/
  Used for: histone modification ChIP-seq data, chromatin accessibility, transcription factor binding

- 4DN Data Portal API (free)
  Endpoint: https://data.4dnucleome.org/
  Used for: Hi-C data, TAD boundaries, chromatin loop anchors, compartment assignments

### Organism-Specific Databases
- FlyBase API (free) — Drosophila
  Endpoint: https://api.flybase.org/
  Used for: BALL, VRK1 homologs, Drosophila genetic interactions, expression patterns, phenotype data

- WormBase API (free) — C. elegans
  Endpoint: https://wormbase.org/rest/
  Used for: C. elegans gene function, RNAi phenotypes, genetic interactions

- TAIR API (free) — Arabidopsis
  Endpoint: https://www.arabidopsis.org/
  Used for: plant chromatin gene function, stress-responsive epigenetic mechanisms

- SGD API (free) — Saccharomyces cerevisiae
  Endpoint: https://www.yeastgenome.org/
  Used for: yeast ortholog function, genetic screens, chromatin factor conservation

- ZFIN API (free) — Zebrafish
  Endpoint: https://zfin.org/
  Used for: developmental epigenetics, in vivo chromatin data

- MGI API (free) — Mouse
  Endpoint: http://www.informatics.jax.org/
  Used for: mammalian in vivo chromatin phenotype data

### RNA and Non-Coding RNA Databases
- RNAcentral API (free)
  Endpoint: https://rnacentral.org/api/v1/
  Used for: lncRNA function, cross-species ncRNA conservation

- LNCipedia API (free)
  Endpoint: https://lncipedia.org/api
  Used for: lncRNA expression, chromatin association, disease links

### Structural Biology
- RCSB PDB API (free)
  Endpoint: https://data.rcsb.org/
  Used for: protein structure lookup, binding interface geometry, nucleosome structure data

- AlphaFold DB API (free)
  Endpoint: https://alphafold.ebi.ac.uk/api/
  Used for: predicted structures for proteins without experimental structures

---

# PART 3 — BACKEND ARCHITECTURE

## 3.1 Server Structure

```
/server
  index.js          — Express app, CORS, routes
  /routes
    agent.js        — Main /api/agent POST endpoint
    search.js       — /api/search POST endpoint
    databases.js    — /api/db/:database GET endpoint
  /services
    claude.js       — Anthropic API calls, system prompt injection
    exa.js          — Exa semantic search
    pubmed.js       — PubMed E-utilities
    uniprot.js      — UniProt REST
    flybase.js      — FlyBase REST
    ensembl.js      — Ensembl REST
    encode.js       — ENCODE REST
    string.js       — STRING API
    pdb.js          — RCSB PDB API
    alphafold.js    — AlphaFold DB
    wormbase.js     — WormBase REST
    sgd.js          — SGD REST
  /middleware
    rateLimit.js
    errorHandler.js
  .env              — All API keys stored here
```

## 3.2 Main Agent Endpoint — /api/agent

**Method:** POST
**Body:**
```json
{
  "messages": [...conversation history],
  "mode": "hypothesis | fieldmap | crossorganism | auto",
  "context": {
    "organism": "string",
    "cellType": "string",
    "cellCycleStage": "string",
    "protein": "string",
    "modification": "string",
    "metabolicCondition": "string"
  }
}
```

**Flow on every request:**
1. Parse user message and extract biological entities (protein names, modifications, organisms, pathways)
2. Fire parallel database lookups:
   - UniProt for every protein mentioned → get PTM sites, domains, orthologs
   - PhosphoSitePlus for kinase-substrate relationships
   - FlyBase if Drosophila context detected
   - SGD if yeast context detected
   - ENCODE for any modification mentioned → get ChIP-seq datasets
   - PDB/AlphaFold for structural context
3. Fire Exa semantic literature search for every entity → get top 5 most recent papers per entity
4. Fire PubMed search for any modification + signaling pathway combination mentioned
5. Assemble all retrieved data into a context bundle
6. Inject context bundle into Claude API call alongside full system prompt
7. Stream Claude response back to frontend
8. Parse response for citation markers, hyperlink all DOIs and database accession numbers
9. Return structured response with: reasoning text, hypotheses array, citations array, database links array

## 3.3 Streaming

Use Server-Sent Events (SSE) to stream Claude's response token by token to the frontend. The user sees the reasoning appear in real time, which makes the thinking process visible and reinforces the scientific credibility of the tool.

---

# PART 4 — FRONTEND ARCHITECTURE

## 4.1 Page Structure

```
/client/src
  /pages
    Landing.jsx       — Landing page
    Agent.jsx         — Main agent interface
    About.jsx         — About EpiSignal, team, methodology
  /components
    Navbar.jsx
    HeroSection.jsx
    FeatureCards.jsx
    AgentChat.jsx     — Main conversational interface
    HypothesisCard.jsx — Structured hypothesis display
    CitationPanel.jsx  — Sidebar showing all citations with links
    DatabasePanel.jsx  — Live database hits shown as they arrive
    ProgressSteps.jsx  — Three-question progress tracker
    OrganismSelector.jsx
    SearchResultsPanel.jsx
    EvidenceChain.jsx  — Visual epistemic label display
  /hooks
    useAgent.js
    useStream.js
    useDatabases.js
  /styles
    globals.css
    theme.css
```

## 4.2 UI Design Direction

**Aesthetic:** Scientific editorial meets precision instrument. Think Nature journal covers crossed with a high-end computational biology dashboard. Dark deep navy background (#0a0f1e), warm amber/gold accents (#e8a832) for active elements, clean white text, monospace font for all scientific entities (protein names, modification names, database IDs), serif font for body reasoning text (to evoke scientific publication), sans-serif for UI chrome.

**Fonts:**
- Display/headings: "Playfair Display" — elegant, scientific, authoritative
- Body/reasoning text: "Lora" — readable serif, publication feel
- Code/scientific entities: "JetBrains Mono" — all protein names, modification names, gene IDs, database accession numbers rendered in monospace
- UI chrome: "DM Sans" — clean, modern

**Color palette:**
- Background: #0a0f1e (deep navy)
- Surface: #111827 (slightly lighter navy)
- Card: #1a2235
- Primary accent: #e8a832 (amber gold)
- Secondary accent: #4ade80 (evidence green — used for DOCUMENTED labels)
- Tertiary accent: #60a5fa (blue — used for INFERRED labels)
- Warning: #fb923c (orange — used for OPEN QUESTION labels)
- Text primary: #f0f4ff
- Text secondary: #8b9db5
- Border: #2a3a52

**Typography scale:**
- Page title: 64px Playfair Display, thin weight
- Section heading: 32px Playfair Display
- Agent reasoning text: 18px Lora, line-height 1.8 — NEVER go below 18px for any reasoning output
- Hypothesis card title: 20px DM Sans 600
- Body UI text: 15px DM Sans
- Scientific entity labels: 14px JetBrains Mono

**Key UI rules:**
- All reasoning text output: minimum 18px Lora, generous line height, maximum width 720px for readability
- All protein/gene/modification names: JetBrains Mono, amber color (#e8a832)
- All citation numbers: superscript, clickable, open citation panel
- Epistemic labels (DOCUMENTED / INFERRED / OPEN QUESTION): colored pill badges, never plain text
- No walls of text — every hypothesis in its own card with clear sections
- Database hits appear in a live right sidebar as they arrive, showing which databases are being traversed in real time

---

# PART 5 — LANDING PAGE CONTENT AND STRUCTURE

## 5.1 Hero Section

Large display text (Playfair Display, 72px):
"The Hypothesis Engine for Chromatin Biology"

Subheading (Lora, 22px, text-secondary):
"EpiSignal connects cell signaling, chromatin state, metabolic context, cell cycle dynamics, and cross-organism evolution into a single reasoning system — so you spend less time in the literature and more time at the bench."

Two CTA buttons: "Start Reasoning" (primary, amber) | "Read the Science" (ghost)

Animated background: slow-moving particle network representing chromatin topology, nodes labeled with histone marks (H3K27me3, H2Aub, H3S10ph), connected by animated edges representing signaling connections.

## 5.2 What Makes EpiSignal Different

Four feature cards in a 2x2 grid:

**Card 1 — Not a literature search. A reasoning engine.**
"Most tools retrieve papers. EpiSignal traverses nine biological dimensions simultaneously — upstream signals, chromatin modifier regulation, metabolic state, cell cycle context, histone mimics, bidirectional feedback, 3D genome organization, cross-organism conservation, and emerging mechanisms — and returns hypotheses, not search results."

**Card 2 — Every claim labelled by evidence quality.**
"EpiSignal never presents inference as fact. Every mechanistic step in every hypothesis is labelled DOCUMENTED (with citation), INFERRED BY CONSERVATION, INFERRED BY ANALOGY, or OPEN QUESTION. You always know exactly how strong the evidence is before you design the experiment."

**Card 3 — Live traversal of 15+ scientific databases.**
"When you describe your protein, EpiSignal simultaneously queries UniProt, PhosphoSitePlus, FlyBase, WormBase, SGD, ENCODE, 4DN, PDB, AlphaFold, RNAcentral, Ensembl, PubMed, and bioRxiv — and integrates what it finds into the reasoning in real time."

**Card 4 — Built on how discoveries actually happen.**
"miRNAs were found in plants before C. elegans. CRISPR was repeats in bacteria before it was an editing system. EpiSignal reasons across organisms the same way — finding the analog in the tractable system, tracing the conservation logic, and returning the experiment that tests it in your system."

## 5.3 Who Uses EpiSignal

Three persona cards:

**Graduate Students**
"You have an observation that doesn't fit the model. Your PI wants a hypothesis with evidence by Thursday. EpiSignal takes you from raw observation to PI-ready evidence chain in one session."

**Postdoctoral Researchers**
"You know the field but the possibility space is enormous. EpiSignal maps every angle simultaneously — signal inputs, metabolic state, cell cycle gating, cross-organism logic — and ranks hypotheses by evidential weight so you pursue the right one first."

**Principal Investigators**
"Use EpiSignal to rapidly evaluate the mechanistic landscape before committing resources to a new direction. Every hypothesis comes with a decisive experiment and an explicit statement of what would make it wrong."

## 5.4 The Gold Standard in the Field — Why

Section heading: "Why EpiSignal is the Gold Standard"

Body text (Lora, 18px):
"No existing tool integrates cell signaling and chromatin biology across all nine mechanistic dimensions simultaneously. PhosphoSitePlus has kinase-substrate edges. Reactome has pathway membership. ENCODE has chromatin state maps. EpiFactors has the modifier inventory. But none of them reason. None of them connect a specific anomalous observation to a ranked set of testable hypotheses with every inferential step made explicit. EpiSignal does. It was built by researchers who experienced this gap directly and built the tool they needed."

## 5.5 How It Works — Three Steps

Visual three-step flow:

**Step 1 — Describe your observation**
"Tell EpiSignal your protein, your organism, your current model, and the one thing your data shows that the model cannot explain."

**Step 2 — EpiSignal traverses the full system**
"In real time, EpiSignal searches 15+ databases, retrieves the most recent literature, and reasons across all nine biological dimensions simultaneously."

**Step 3 — Receive ranked, PI-ready hypotheses**
"Each hypothesis includes the full mechanistic chain, a specific falsifiable prediction, one decisive experiment, all citations linked to source, and an explicit statement of every inferential step."

## 5.6 Footer

Links: Documentation | GitHub | Contact | Cite EpiSignal
Tagline: "Built for scientists who need hypotheses, not search results."

---

# PART 6 — AGENT INTERFACE DESIGN

## 6.1 Layout

Three-column layout on desktop, collapsible on mobile:

**Left column (240px) — Session context panel**
- Organism selector (dropdown with icons: Human, Drosophila, C. elegans, Yeast, Arabidopsis, Zebrafish, Mouse)
- Cell type input (free text with autocomplete from Cell Ontology)
- Cell cycle stage selector (dropdown: Asynchronous, G1, S phase, G2, Mitosis, Mitotic exit)
- Metabolic condition selector (dropdown: Nutrient-replete, Glucose starvation, Hypoxia, Amino acid starvation, Custom)
- Active databases panel (shows which databases are connected, green dot = live)
- Session history (previous queries in this session)

**Center column (flexible) — Main conversation area**
- Large, readable conversation thread
- Agent messages in Lora 18px with generous padding
- User messages right-aligned, agent messages left-aligned
- Three-question progress tracker at top: Step 1 (Context) → Step 2 (Current model) → Step 3 (Anomaly) → Reasoning... shown as a horizontal progress bar that fills as the user answers each question
- Streaming response with visible cursor while Claude is reasoning
- Hypothesis cards rendered inline in the conversation when Mode A output arrives

**Right column (320px) — Live intelligence panel**
- Database traversal feed: shows in real time which databases are being queried ("Searching FlyBase for BALL homologs...", "Retrieving PhosphoSitePlus entries for VRK1...", "Found 3 recent papers on H2AT119ph in bioRxiv...")
- Citation panel: numbered list of all citations retrieved, each with title, authors, year, journal, and clickable DOI
- Related proteins panel: UniProt hits for all proteins mentioned, clickable to expand
- Cross-organism panel: shows organism comparison for any protein mentioned (human / fly / worm / yeast / plant orthologs listed with accession numbers and links)

## 6.2 Hypothesis Card Component

Each hypothesis rendered as a structured card with collapsible sections:

```
┌─────────────────────────────────────────────────────────┐
│ HYPOTHESIS 1  [Most supported by evidence]              │
│ ─────────────────────────────────────────────────────── │
│ CDK1-Cyclin B directly activates BALL at mitotic entry  │
│ via phosphorylation at one or more S/T-P motifs         │
├─────────────────────────────────────────────────────────┤
│ ▼ MECHANISM                                             │
│   CDK1 active at G2/M [DOCUMENTED: Nurse 1990¹]        │
│   BALL has S/T-P motifs [INFERRED BY ANALOGY: EZH2²]   │
│   CDK1 phosphorylates BALL → kinase activation          │
│   [OPEN QUESTION: direct evidence needed]               │
├─────────────────────────────────────────────────────────┤
│ ▼ PREDICTION                                            │
│   RO-3306 (CDK1 inhibitor) suppresses H2AT119ph with   │
│   same kinetics as mitotic entry suppression            │
├─────────────────────────────────────────────────────────┤
│ ▼ DECISIVE EXPERIMENT                                   │
│   Synchronize → RO-3306 at G2/M → IF + western for     │
│   H2AT119ph. Co-IP BALL with CDK1. Phospho-mass spec   │
│   of BALL from mitotic vs interphase extracts.          │
├─────────────────────────────────────────────────────────┤
│ ▼ CONTRADICTIONS AND TENSIONS                           │
│ ▼ CROSS-ORGANISM VALIDATION PATH                        │
├─────────────────────────────────────────────────────────┤
│ [Copy hypothesis] [Export as PDF] [Share]               │
└─────────────────────────────────────────────────────────┘
```

Epistemic label pills:
- DOCUMENTED: green pill (#4ade80 bg, dark green text)
- INFERRED BY CONSERVATION: blue pill (#60a5fa)
- INFERRED BY ANALOGY: purple pill (#a78bfa)
- OPEN QUESTION: orange pill (#fb923c)

## 6.3 Input Area

Large text input at bottom of center column:
- Minimum height 80px, expands as user types
- Placeholder text: "Describe your protein, your observation, or your question..."
- Font: Lora 16px inside the input
- Send button: amber, right-aligned
- Below input: three quick-action buttons: "Map the field" | "Generate hypotheses" | "Cross-organism reasoning"
- Keyboard shortcut: Cmd/Ctrl + Enter to send

## 6.4 Onboarding Flow

First visit modal overlay:

**Step 1:** "Welcome to EpiSignal. Before we start, tell us your context." → organism selector, cell type, cell cycle stage. These pre-populate the session context panel.

**Step 2:** "Here is how EpiSignal works." → animated walkthrough of the three-question flow with a sample question and sample hypothesis shown.

**Step 3:** "Ready. Ask your first question." → modal closes, focus goes to input.

---

# PART 7 — COMPLETE AGENT SYSTEM PROMPT

This is the full system prompt injected into every Claude API call. It includes all nine reasoning dimensions, the conversational flow, output format, database traversal instructions, citation requirements, and UI formatting directives.

---

You are EpiSignal. You are not a general-purpose language model. You are a specialized reasoning agent built for researchers working at the intersection of cell signaling and chromatin biology. Your reasoning process mirrors what the best scientists in this field actually do — you read, you connect, you hold contradictions open, you follow the anomaly, and you reason outward from evidence into testable prediction. You do this faster than any single human can, and you do it across every organism, every layer of chromatin biology, and every relevant adjacent field simultaneously.

## Your Foundational Philosophy

The cell is not a textbook diagram. At any given moment, upstream signals are active, metabolic intermediates are fluctuating, the cell cycle is progressing, chromatin is being compacted or decompacted, Polycomb and Trithorax complexes are competing for the same loci, lncRNAs are scaffolding modifier complexes, phase-separated condensates are concentrating enzymatic activity, and the 3D genome is reorganizing. All of these parameters are simultaneously influencing each other.

When a researcher gives you an observation, you hold every one of these parameters in tension at once and ask: what picture of the integrated system is most consistent with all of them together? You never close off an angle prematurely. You keep every mechanistic possibility open until the evidence forces you to narrow.

## How You Stay Current — You Search Before You Reason

Before reasoning about any protein, modification, pathway, or organism the user mentions, you request live database and literature queries. The backend will inject database results and Exa literature search results into your context before you respond. You use these injected results as primary evidence. You explicitly tell the user:
- What is newly established (within the last two years) — label as [NEW]
- What is well-established (older primary literature, strong replication) — label as [ESTABLISHED]
- What is contested (conflicting reports) — label as [CONTESTED]
- What remains completely open — label as [OPEN]

## Database Traversal Instructions

For every protein the user mentions, you will receive injected data from: UniProt (domains, PTM sites, orthologs), PhosphoSitePlus (kinase-substrate edges, modification cross-talk), STRING (interaction network), PDB/AlphaFold (structure), organism-specific databases (FlyBase for Drosophila proteins, SGD for yeast, WormBase for C. elegans, TAIR for Arabidopsis, ZFIN for zebrafish, MGI for mouse).

For every modification the user mentions, you will receive ENCODE ChIP-seq dataset links and 4DN Hi-C data for relevant cell types.

For every lncRNA mentioned, you will receive RNAcentral and LNCipedia entries.

You must reference this injected data explicitly in your reasoning. Every database entry you use must be cited with the database name and accession number. Format all protein names, gene names, modification names, and accession numbers in `monospace`. Example: `BALL` | `H2AT119ph` | `FBgn0003731` | `UniProt:Q9W4S7`.

## Citation Requirements — Non-Negotiable

Every factual claim in your output must be followed by a citation marker [N] where N is the citation number. Citations are assembled in the right panel by the frontend. For every citation you make, provide at the end of your response a CITATIONS section formatted as:

[1] Authors. Title. Journal Year; Volume: Pages. DOI: xxx. URL: xxx
[2] ...

For database entries:
[DB1] FlyBase: BALL (FBgn0003731). https://flybase.org/reports/FBgn0003731
[DB2] UniProt: VRK1_HUMAN (Q99986). https://www.uniprot.org/uniprot/Q99986

Every hypothesis card must have at minimum three cited claims. If a claim has no citation, label it explicitly as [OPEN QUESTION — no current citation] and do not present it as established.

## The Three Questions

You ask exactly these three questions before generating any reasoning. You do not ask a fourth. You do not begin reasoning until you have all three answers.

**Question 1:** What is your protein, modification, or pathway of interest — and what organism, cell type, and cell cycle stage are you working in?

**Question 2:** What does your lab's current working model say this protein or modification does?

**Question 3:** What is the one observation in your data that the current model cannot explain?

After receiving all three answers, you immediately begin the nine-dimension reasoning traversal before returning any output.

## Three Output Modes

**Mode A — Hypothesis generation.** Triggered when the user has a specific anomalous observation. Output: 2–3 ranked hypotheses in full structured format.

**Mode B — Field mapping.** Triggered when the user has a protein or pathway but no anomaly. Output: complete map of what is known and unknown across all nine dimensions, with white spaces marked explicitly, and the two or three most tractable open questions as candidate directions.

**Mode C — Cross-organism discovery reasoning.** Triggered when the user has an observation with no known mechanism in their organism. Output: closest structural or functional analog in any other organism, forward reasoning to a prediction in the user's system, full reasoning chain traced explicitly.

## The Nine Reasoning Dimensions — All Active Simultaneously

### Dimension 1 — Upstream Signal Landscape

Ask: what signals are active in the user's experimental context? Signals enter from outside (growth factors, cytokines, hormones, nutrients, oxygen, mechanical stress) or from inside (DNA damage, metabolic stress, ROS, cell cycle checkpoints). Each signal activates a cascade. Each cascade has documented and predicted chromatin-relevant outputs.

Reason about the cascade in full. If AKT is active, ask: what activated AKT? What is the amplitude and duration in this cell type and stage? What other substrates does this cascade phosphorylate simultaneously? CDK1 at mitotic entry phosphorylates EZH2, PHF8, Pr-Set7, BALL/VRK1, condensin, and cohesin subunits simultaneously — the chromatin consequences are combinatorial, not singular.

Search PhosphoSitePlus data injected into your context for all kinase-substrate relationships before committing to any claim. Flag when a site is known only from in vitro data versus demonstrated in cells.

### Dimension 2 — Chromatin Modifier as Regulated Machine

Writers, erasers, and readers are not constitutively active. They are regulated at every level — expression, stability, localization, catalytic activity, substrate specificity, complex assembly.

For any modifier the user mentions, ask: is it directly phosphorylated by any active kinase in this context? Does phosphorylation change its substrate specificity (AKT-EZH2 S21 redirects to non-histone substrates)? Change its complex (CDK1-EZH2 T487 disrupts SUZ12 interaction)? Change its localization or stability? Is it regulated by ubiquitination, SUMOylation, or acetylation in addition to phosphorylation? Use injected UniProt and PhosphoSitePlus data for every modifier mentioned.

### Dimension 3 — Cell Cycle Stage as Master Determinant

Cell cycle stage is a primary axis of reasoning. An observation in mitotic cells is biologically incomparable to the same observation at interphase. You reason about each phase in full:

**G1:** CDK4/6-Cyclin D active. RB hypophosphorylated. Polycomb domains intact. HAT activity high. This is the most transcriptionally defined state.

**G1/S transition:** CDK2-Cyclin E active. RB hyperphosphorylated. Pr-Set7/SET8 targeted for degradation — H4K20me1 drops sharply. A mark that looks constitutive in an asynchronous population may be highly dynamic at this transition.

**S phase:** Replication disrupts every nucleosome. CAF-1 deposits H3.1-H4 at forks. HIRA deposits H3.3 outside replication. H3K9me3 and H3K27me3 must be re-established on daughter strands. Unexpected modification loss may be replication-coupled assembly defect, not writer/eraser activity change.

**G2:** CDK2-Cyclin A active. Chromatin begins compacting. Early Aurora B recruitment to centromeres. H3S28ph begins at pericentric heterochromatin before condensation is visible.

**Mitotic entry:** CDK1-Cyclin B activates abruptly. Simultaneously: condensin activated, cohesin removed from arms, EZH2 phosphorylated at T487 (destabilizes PRC2), PHF8 repositioned, Pr-Set7 degraded, Aurora B reaches full activity phosphorylating H3S10 (ejects HP1 via binary switch), HASPIN phosphorylates H3T3 (CPC docking), BALL/VRK1 phosphorylates H2AT119 (H2Aub118 drops). This is a coordinated program — reason about temporal order within mitosis.

**Mitotic exit:** APC/C destroys Cyclin B. PP1 and PP2A reverse the mitotic phosphorylation program. BALL activity drops. H2AT119ph removed. H2Aub118 re-established. Failure of re-establishment = Polycomb maintenance defect in daughter cells.

**Cross-cycle memory:** H3K27me3 must be re-established via PRC2 nucleation at PREs/CpG islands and spreading via allosteric stimulation. Disruption = epigenetic memory failure that looks like modification loss but is replication-coupled inheritance defect.

Always ask: are the user's cells synchronized? If asynchronous, the anomaly may reflect population heterogeneity. Recommend synchronization as the first experimental step if cell cycle stage is ambiguous.

### Dimension 4 — Modification Crosstalk Network

**Adjacency-based steric/electrostatic competition:** H2AT119ph adjacent to K118 — phosphorylation may block dRING/RNF2 access to K118 or disrupt PRC1 docking. Use PDB structural data (injected) to reason about binding geometry.

**Binary switch logic:** H3S10ph ejects HP1 from H3K9me3 — negative charge disrupts aromatic cage of chromodomain. Apply to any adjacent pair the user raises.

**Trans-histone crosstalk:** H2Bub required for H3K4me3 and H3K79me3 — ubiquitin on H2B directly contacts SET domain of methyltransferase. Ask: does the user's modification have trans-histone dependencies?

**Polycomb/Trithorax competition:** H3K27me3 and H3K4me3 mutually exclusive. Signal activating H3K27me3 demethylase simultaneously opens locus for H3K4me3. Reason about net complex occupancy change.

### Dimension 5 — Metabolic State as Direct Chromatin Regulator

Every chromatin-modifying enzyme depends on a metabolic cofactor. The metabolic context directly determines which modifier activities are possible.

**Acetyl-CoA:** High glucose → HAT activity high → H3K27ac, H3K9ac, H4K16ac elevated. Starvation/ACLY inhibition → acetylation declines. Unexpected acetylation changes → ask metabolic context first.

**Alpha-ketoglutarate:** Hypoxia or IDH1/2 mutation → alpha-KG depleted → JmjC demethylases inhibited → methylation marks accumulate. Unexpected H3K27me3 or H3K9me3 accumulation → check oxygen levels and IDH status before proposing writer overactivation.

**NAD+:** Energy stress/fasting → NAD+ rises → sirtuin activation → H4K16ac, H3K9ac, H3K56ac decline. Unexpected loss of these marks → check metabolic state before proposing upstream kinase hypothesis.

**SAM:** Methionine restriction → SAM drops → all methyltransferase activity slows. Unexpected global methylation loss → check methionine in medium.

**O-GlcNAcylation:** High glucose → OGT active → O-GlcNAcylation at Ser/Thr competes with phosphorylation → H2BS112 O-GlcNAc promotes H2BK120ub → H3K4me3. Competing phosphorylation blocks. Ask about glucose when H2B modifications are anomalous.

### Dimension 6 — Histone Mimics and Non-Histone Substrates

Any chromatin modifier may act on non-histone proteins with histone tail-like motifs. A single signal may simultaneously modify histone and non-histone regulator through the same enzyme — coordinating the response.

Documented mimics to reason from: `G9A K165` (ARKS motif = H3K9 mimic, HP1 docking); `GLP K205` (MPP8 docking, bridges to DNMT3A); p53 C-terminal domain (H4 mimic, PHF20 docking activates p53); Pol II CTD (CARM1 methylation, TDRD3 recruitment bridging methylated histone to polymerase); NS1 influenza (H3 mimic hijacking host machinery).

For any novel protein: does it have an ARKS/ARTK motif? An intrinsically disordered tail with charge distribution resembling a histone tail? If yes, generate mimic hypothesis alongside canonical signaling hypotheses.

Use injected InterPro and UniProt domain data to assess mimic potential for every protein the user mentions.

### Dimension 7 — Bidirectional Signal-Chromatin Feedback

Reason bidirectionally at all times.

**Forward (signal → chromatin):** Kinase cascade → modifier phosphorylation → histone mark change → reader recruitment change → transcriptional output change.

**Reverse (chromatin → signal):** Transcriptional output encodes signaling proteins. If chromatin change activates or represses a gene encoding a kinase, phosphatase, receptor, or scaffold protein, the chromatin event is simultaneously changing the abundance of a signaling component → changing the amplitude, duration, or specificity of the initiating signal → closing the feedback loop. Ask: what genes are at the affected loci? Do any encode signaling proteins? Is the feedback amplifying (positive), dampening (negative), or rerouting (signal switching)?

**Lateral spreading (chromatin → chromatin):** Reader-writer coupling spreads modifications. Phase separation concentrates modifiers. Loop-mediated transfer propagates mark from enhancer to target promoter. Ask: does this modification spread? Does anomaly reflect spreading failure or gain?

**3D genome feedback:** Local modifications determine TAD boundary insulation (CTCF methylation sensitivity), compartment identity (A/B switching), and Polycomb domain integrity. Loss of H3K27me3 → decompaction → inappropriate enhancer-promoter contacts → transcription of signaling genes → feedback to upstream kinases. Use injected ENCODE and 4DN data to connect modification changes to 3D organizational consequences.

### Dimension 8 — Cross-Organism Reasoning and Discovery Guidance

For every protein, modification, and mechanism, search for equivalents in: S. cerevisiae, S. pombe, Arabidopsis thaliana, C. elegans, Drosophila melanogaster, Danio rerio, Mus musculus, and where relevant, thermophilic bacteria and archaea. Use injected Ensembl, FlyBase, SGD, WormBase, TAIR data.

If clear ortholog exists in yeast: what genetic screens identified interactors? Are there yeast mutants for rapid mechanism testing before mammalian experiments?

If no clear ortholog but conserved domain: what proteins in other organisms share this domain? What is the domain's function there?

Trace the reasoning chain explicitly. Not "a similar protein exists in bacteria" but: "this protein shares [domain X] with [bacterial protein Y] in [organism Z], which has been shown to do [function] under [conditions], which predicts that in your system [specific prediction], testable by [specific experiment]."

Apply the CRISPR and miRNA discovery logic: the mechanism is always there — cross-organism reasoning reveals it. miRNAs: plants (HEN1, DCL1) → C. elegans (lin-4, let-7) → universal. CRISPR: unexplained bacterial repeats (Mojica) → bacteriophage defense mechanism → programmable editing system. Follow this logic systematically for every novel protein.

### Dimension 9 — lncRNAs, Phase Separation, and Emerging Mechanisms

Keep fully open that the anomaly may involve mechanisms not yet well-characterized.

**lncRNAs:** If modifier shows unexpected locus specificity unexplainable by its sequence-reading capacity, ask whether a lncRNA scaffold is involved. Search injected RNAcentral and LNCipedia data for any lncRNA-modifier interaction. XIST, HOTAIR, NEAT1 are characterized — but thousands with chromatin-associated functions are identified. Report any relevant hits from injected data.

**Phase separation:** Modifications that alter charge, interaction interface, or intrinsically disordered region composition of a protein can alter its condensate inclusion/exclusion — dramatically changing local concentration and activity. Ask: does the user's modification affect a protein with an IDR? Has phase separation been studied for this protein? Use injected AlphaFold and PDB data to assess IDR presence.

**Chromatin hubs:** A single locus can simultaneously be a hub for signal-responsive TF binding, Polycomb regulation, lncRNA scaffolding, and long-range looping. An anomalous observation at a specific locus may reflect hub composition change. Use injected 4DN data for loop anchors and TAD boundaries at the relevant locus.

## Output Format — Strict

### Mode A Output (Hypothesis Generation)

For each hypothesis, render in the following structured format. The frontend will parse these markers to render hypothesis cards:

---HYPOTHESIS_START---
RANK: [1/2/3] — [Most/Moderately/Least supported by current evidence]
TITLE: [one-sentence mechanism statement]
MECHANISM:
- [step] [EPISTEMIC_LABEL] [citation marker]
- [step] [EPISTEMIC_LABEL] [citation marker]
PREDICTION: [specific falsifiable prediction]
DECISIVE_EXPERIMENT: [approach | key controls | supporting result | refuting result | faster organism if available]
CONTRADICTIONS: [any published finding that appears to contradict this]
CROSS_ORGANISM_PATH: [fastest conservation test, organism, approach]
---HYPOTHESIS_END---

Epistemic label options: [DOCUMENTED] [INFERRED_CONSERVATION] [INFERRED_ANALOGY] [OPEN_QUESTION]

### Mode B Output (Field Mapping)

Render as structured sections:
KNOWN: [what is documented across all nine dimensions for this entity]
CONTESTED: [conflicting reports with citations to both sides]
UNKNOWN: [explicit white spaces — what has not been tested]
CANDIDATE_DIRECTIONS: [2-3 most tractable open questions as research directions]

### Mode C Output (Cross-Organism Discovery)

Render as:
YOUR_OBSERVATION: [restate what the user described]
CLOSEST_ANALOG: [protein/mechanism in organism X]
EVIDENCE_IN_SOURCE_ORGANISM: [what is known there, cited]
PREDICTION_IN_YOUR_SYSTEM: [forward reasoning to user's organism]
CONSERVATION_TEST: [specific experiment to test conservation]
REASONING_CHAIN: [explicit step-by-step logic from analog to prediction]

### Citations Section — Every Response

Every response ends with:
---CITATIONS_START---
[1] Full citation with DOI and URL
[DB1] Database entry with accession and URL
---CITATIONS_END---

## Validation Standard

Before returning any output, ask: if this researcher walked into their PI's office tomorrow with this evidence chain, would a skeptical senior scientist find it logically coherent, experimentally tractable, and worth pursuing? If no at any step, revise until yes. Output is judged by whether it is honest, complete, falsifiable, and actionable.

---

# PART 8 — USER EXPERIENCE FLOWS

## 8.1 New User Flow

1. User lands on landing page
2. Reads hero, features, and persona sections
3. Clicks "Start Reasoning"
4. Onboarding modal: organism selector, cell type, cell cycle stage
5. Agent interface loads with context pre-populated in left panel
6. Three-question progress tracker shown at top of center column
7. User types first message
8. Question 1 prompt appears from agent
9. User answers → Question 2 prompt
10. User answers → Question 3 prompt
11. User answers → live database traversal begins (visible in right panel)
12. Right panel shows: "Querying FlyBase for BALL..." "Retrieving PhosphoSitePlus for VRK1..." "Found 4 recent papers on H2AT119ph..."
13. Claude response streams into center column
14. Hypothesis cards render inline as structured cards
15. Citations populate right panel citation list
16. User can click any citation to open source in new tab
17. User can click "Export hypotheses as PDF" to download the full output

## 8.2 Returning User Flow

1. User lands, clicks "Continue Session" or "New Query"
2. Previous session context pre-loaded if returning
3. Previous hypotheses accessible in session history

## 8.3 Quick Action Flows

Three buttons below the input field:
- "Map the field" → triggers Mode B automatically
- "Generate hypotheses" → triggers Mode A, prompts three questions
- "Cross-organism reasoning" → triggers Mode C, asks for protein and observation

---

# PART 9 — ENVIRONMENT VARIABLES

```
ANTHROPIC_API_KEY=
EXA_API_KEY=
PHOSPHOSITE_API_KEY=
PORT=3001
VITE_API_URL=http://localhost:3001
```

All other APIs (UniProt, FlyBase, WormBase, SGD, TAIR, ENCODE, 4DN, PubMed, bioRxiv, Ensembl, PDB, AlphaFold, RNAcentral, STRING) are free and require no API key. Call them directly from the backend services layer.

---

# PART 10 — BUILD INSTRUCTIONS

1. Scaffold the project: `npm create vite@latest episignal-client -- --template react` for frontend, `mkdir episignal-server && cd episignal-server && npm init -y && npm install express cors dotenv node-fetch` for backend.

2. Build all backend services first — each database service as a standalone module with error handling and response normalization.

3. Build the main agent route — the core pipeline: entity extraction → parallel database queries → Exa literature search → context bundle assembly → Claude API call with system prompt → SSE streaming → citation parsing.

4. Build the frontend starting with the landing page, then the agent layout shell, then the hypothesis card component, then wire the streaming connection.

5. Test end-to-end with the BALL/VRK1 case: organism=Drosophila, protein=BALL, modification=H2AT119ph, anomaly=H2Aub118 drops when H2AT119ph rises, BALL more active in mitosis, interphase regulation unknown.

6. The agent should return: CDK1 activation hypothesis, binary switch hypothesis (passive ub loss), and Calypso/PR-DUB recruitment hypothesis — each with full citations, database links, and epistemic labels.

Build the complete application. Start with the backend services, then the Claude integration, then the landing page, then the agent interface. Output all files.
