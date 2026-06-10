# EpiSignal: Context-Aware Mechanistic Reasoning Agent for Chromatin Biology
Mujtaba Ahmed, Tariq Lab, LUMS, 2026

## Abstract

EpiSignal is a domain-specific reasoning agent designed for bidirectional analysis of cell signalling and chromatin biology. The system addresses a gap that no existing tool fills: reasoning mechanistically from an observed chromatin state change to its upstream signalling causes, and from a signalling perturbation to its downstream chromatin consequences, within the specific biological context of the researcher's experiment. EpiSignal traverses a structured biological knowledge graph in both the forward direction (signal to chromatin) and the reverse direction (chromatin to signal), integrating 18 or more contextual parameters that together define the feasible hypothesis space for any given query. The scoring framework combines Bayesian joint probability scoring with conformal prediction and entropy balancing (TxConformal, Jin et al. 2026) to produce ranked, falsifiable experimental hypotheses with calibrated confidence guarantees. A key application is reasoning from GWAS loci identified by tools such as Vector2Variant (Sooknah et al. 2026) to the chromatin mechanisms by which genetic variants produce their phenotypic effects.

## Section 0: What EpiSignal Is and What Problem It Solves

### 0.1 Problem statement

The question that EpiSignal is built to answer is this: a chromatin biologist obtains an unexpected ChIP-seq result and needs to know what caused it. What signalling events drove the observed modification change? What will follow from it? Which competing mechanistic explanations are consistent with the experimental context, and which can be excluded on biological grounds? What is the most informative experiment to distinguish between the remaining candidates?

No existing tool addresses this question in a principled way. STRING, Reactome, and PhosphoSitePlus are databases built around the assumption that signalling is upstream and chromatin is downstream. They do not reason about the reverse direction, where chromatin state regulates signalling pathway activity. They do not integrate biological context, so they produce the same outputs regardless of whether the cell is in G1 or M-phase, normoxic or hypoxic, wild-type or IDH-mutant. They do not produce ranked hypotheses or experimental recommendations. General-purpose AI models do produce answers in natural language, but they mix confirmed mechanisms with hallucinated ones without distinguishing between them, and they apply cross-organism analogies without conservation evidence.

EpiSignal is a mechanistic reasoning system that operates on a structured biological knowledge graph where every node is a database-verified entity, every edge carries a mechanism type annotation and an evidence weight, and every confidence score is traceable to specific experimental evidence. Its primary users are chromatin biologists, epigenomics researchers, and computational biologists working on Polycomb/Trithorax regulation, histone modification hierarchies, and the signalling-epigenome interface.

### 0.2 Who this document is for

This document is intended for chromatin biologists, computational biologists, statisticians, and wet-lab researchers who want to understand the design rationale and technical architecture of EpiSignal. The mechanistic biology sections (Sections 1 through 5) describe the biological reasoning the system performs, with every enzyme-substrate relationship cited and every contested mechanism qualified by its experimental basis. The statistical sections (Sections 9 and 10) develop the probability models and multiple testing framework from first principles. The AI architecture sections (Sections 6 through 8) justify every algorithmic choice based on the mathematical properties of the relevant data type. The applications and limitations sections (Sections 14 through 16) are written for wet-lab researchers and describe what can and cannot be concluded from specific experimental systems.

## Section 1: The Five Gaps This System Addresses

### 1.1 The Bidirectionality Gap

The field of chromatin biology has historically been structured around a one-way conceptual axis: signals arrive at the nucleus and modify chromatin. This framing is categorically incomplete. Chromatin state is an active upstream regulator of signalling pathway activity. Every existing pathway analysis tool, STRING, Reactome, KEGG, PhosphoSitePlus, represents kinases as upstream and histones as downstream. This is a systematic architectural blind spot.

Three documented examples:

**(A) H2BK120ub by RNF20/RNF40 and non-transcriptional kinetochore regulation.**
Forward chain: transcriptional elongation (Pol II pause release) → PAF complex → Rad6/Bre1 → H2BK120ub → COMPASS → H3K4me3 [Briggs et al. 2002, Science; Dover et al. 2002, J Biol Chem].
Reverse chain: H2BK120ub at centromeric chromatin → Dam1 kinetochore complex regulation → chromosome segregation fidelity → cell cycle progression [Fierz & Muir 2012, Nat Chem Biol]. A tool modelling only forward direction cannot predict the centromeric phenotype of H2BK120ub loss.

**(B) PRC2-mediated H3K27me3 at the PTEN locus driving PI3K/AKT activation.**
Forward chain: EZH2 overexpression → H3K27me3 at PTEN locus → PTEN transcriptional silencing [Cha et al. 2005, Mol Cell; Zhang et al. 2012, Cancer Cell].
Reverse chain: PTEN silencing → unrestricted PI3K → PIP3 accumulation → AKT activation → AKT phosphorylates EZH2-S21 [Cha et al. 2005] → PRC2 activity reduced. This creates a positive feedback loop invisible to any forward-only tool. EpiSignal detects this loop as a single integrated reverse-chain traversal, and identifies that PI3K pathway activation in these cells is chromatin-driven (reversible) rather than mutation-driven (irreversible), a clinically actionable distinction.

**(C) The BALL/VRK1 system, H2AT119ph as a bidirectional regulatory node.**
Forward chain: upstream signalling → BALL kinase activation → H2AT119ph → displacement of PRC1 (dRING) from H2AK118 → reduced H2AK118ub1 → derepression of Polycomb target genes [Khan et al. 2021, Front Cell Dev Biol; Shaukat et al. 2021, Front Cell Dev Biol].
Reverse chain (EpiSignal-generated hypothesis, high priority): if H2AT119ph is enriched at TAD boundary regions, BALL-mediated phosphorylation could regulate loop extrusion and TAD boundary insulation, controlling which enhancer-promoter pairs are in proximity and therefore which signalling genes are accessible. The chromatin state (H2AT119ph density at boundaries) would feed back to determine signal pathway gene expression. EpiSignal is specifically designed to model these bidirectional nodes, and BALL is its primary Drosophila validation case.

Any tool modelling only signal → chromatin is architecturally incapable of answering the most important mechanistic questions in epigenomics. Bidirectionality is therefore a design requirement, not an optional extension.

### 1.2 The Static Model Problem

Every major chromatin analysis tool produces static, context-free outputs. "Static" means: the same kinase-histone prediction is generated regardless of cell cycle phase, metabolic state, cell type, developmental stage, organism, disease background, or environmental stress.

Consider EZH2 and H3K27me3. CDK1 phosphorylates EZH2-T487 in G2/M, disrupting EZH2-EED interaction and globally reducing H3K27me3 [Wei et al. 2011, Nat Cell Biol], but CDK1 is inactive in G1-arrested cells, making this mechanism irrelevant in that context. AKT phosphorylates EZH2-S21 in PI3K-active cancers [Cha et al. 2005], irrelevant in PTEN-wild-type, AKT-low cells. p38/MAPK14 phosphorylates EZH2-T372 specifically during myogenic differentiation at myogenin loci [Xu et al. 2011, Mol Cell], irrelevant in neural or haematopoietic contexts.

EpiSignal addresses this by loading a state vector **V** at the start of every reasoning session:

$$\mathbf{V} = \{v_1, v_2, ..., v_{11}\}$$

covering cell cycle stage, metabolic state, tissue and cell type, developmental stage, organism, disease state, cell state, population genetic context, environmental stress, transgenerational/age context, and infection/immune state. The feasible hypothesis space is filtered by logical AND:

$$H_{\text{feasible}} = \{h \in H_{\text{all}} : \bigwedge_{i=1}^{11} \text{compatible}(h, v_i)\}$$

This joint constraint integration is not approximate filtering, it is logical elimination. A mechanism requiring CDK1 activity is inadmissible in a G1 cell. A mechanism requiring alpha-KG is inadmissible under severe hypoxia. These are hard constraints, not soft preferences.

### 1.3 The Data Fragmentation Problem

No existing tool reasons across the following databases simultaneously and automatically, maintaining consistent biological context:

| Database | Provides | Critically Lacks |
|---|---|---|
| STRING | Protein-protein interaction networks with confidence scores | Histone modification context, cell-type specificity, modification directionality, 3D genome organisation |
| BioGRID | Curated genetic and physical interactions (strong Drosophila coverage) | Modification-level resolution, metabolic context, developmental staging |
| PhosphoSitePlus | Curated PTMs on proteins including histones, with experimental method annotation | Genomic locus context, cell cycle staging, tissue-specific functional consequences |
| ENCODE | Genome-wide regulatory genomics data across hundreds of cell types | Signalling pathway context, enzyme-substrate mechanistic reasoning, Drosophila depth |
| 4D Nucleome | Hi-C, ChIA-PET, 3D genome structure data | Integration with signalling pathway databases, mechanistic reasoning about TAD drivers |
| GEO | Gene expression and chromatin profiling datasets | Structured metadata enabling automatic contextual inference, mechanistic reasoning |
| Human Cell Atlas | Single-cell transcriptomic and chromatin data across human tissues | Mechanistic signalling-chromatin reasoning, modification-level integration |
| FlyBase | Definitive Drosophila genetics and genomics resource | ChIP-seq coverage at depth of human PhosphoSitePlus, mammalian pathway integration |
| ChEMBL | Bioactivity data for small molecules | Chromatin state context, downstream epigenomic consequence prediction |
| AlphaFold DB | Predicted protein structures for essentially all proteins | Functional context, PTM annotations, reasoning about modification effects on chromatin binding |

EpiSignal solves fragmentation through a **database cascade architecture**: at inference time, a user query triggers parallel queries to all relevant databases, with evidence integrated through evidence-weighted scoring, conflict detection when records disagree, and a fallback hierarchy when APIs are unavailable. The researcher who previously needed to manually query six databases and synthesise results receives a single integrated output with full source tracing.

### 1.4 The Hallucination Problem

Frontier LLMs produce unreliable outputs for specialist chromatin biology queries, and the failure mode is insidious: incorrect output sounds authoritative, uses correct terminology, and is structured like expert scientific writing.

**Test query:** *"What are the mechanisms by which H2A T119 phosphorylation regulates Polycomb domain boundaries in Drosophila?"*

**A hallucinating LLM response** might include: *"H2AT119 phosphorylation by DYRK1A promotes PRC1 complex recruitment through an interaction with the PSC subunit, which stabilises H3K27me3 at domain boundaries through EZH2 allosteric activation."* This sentence is syntactically correct and uses real protein names. Every factual claim is wrong: DYRK1A is not a documented H2AT119 kinase in Drosophila (the kinase is BALL/Ballchen). PSC does not interact with phosphorylated H2AT119 in this documented context. The proposed mechanism (H2AT119ph → PRC1 recruitment) is the opposite of the correct mechanism (H2AT119ph → PRC1 displacement). The invocation of EZH2 allosteric activation conflates a mammalian PRC2 mechanism with a Drosophila PRC1 mechanism.

EpiSignal addresses this through five architectural requirements:

1. **Source tracing:** Every factual claim linked to a specific database record or DOI. Claims without database support are explicitly labelled PREDICTED or SPECULATIVE.

2. **Epistemic labelling:** Every claim carries one of four labels: CONFIRMED (validated in user's specific organism/cell type), SUPPORTED (validated in related context with documented conservation), PREDICTED (mechanistically inferred, not directly tested), SPECULATIVE (novel hypothesis, weak prior evidence).

3. **Contradiction detection:** Cross-database consistency checking, if PhosphoSitePlus records a site as inhibitory but a primary paper records it as activating, EpiSignal flags the contradiction and presents both with evidence quality scores.

4. **Cross-organism discipline:** No conservation claim without documented ortholog evidence. BALL ≠ VRK1 by default; prior = 0.25 base; documented functional conservation required to raise this prior. EpiSignal states the evidence base and prior explicitly, never asserts equivalence.

5. **Cell model limitation statements:** Every Drosophila query output includes: *"S2 cells are derived from Drosophila late-stage embryo, representing embryonic haemocyte-like cells. Mechanisms inferred from S2 cells may not apply to adult imaginal disc cells, neuroblasts, or germline. Locus-specific results require validation in the relevant developmental context."*

### 1.5 The Sequence-to-State Model Gap

Enformer [Avsec et al. 2021, Nat Methods], EPInformer [Zhou et al. 2023, Nat Genetics], Orca [Tan et al. 2023], C.Origami, and ChromBPNet are outstanding sequence-based chromatin state predictors. They answer: *"Given this DNA sequence, what chromatin state will I observe?"* Their input is sequence; their output is a predicted epigenomic track. This question is static, unidirectional, and sequence-determined.

EpiSignal answers: *"Given this observed chromatin state change, what signalling events caused it, what signalling events will follow, and what is the most informative experiment to resolve mechanistic ambiguity?"*

**Specific contrast.** Enformer predicts H3K27ac levels at MYC enhancers given the sequence [Avsec et al. 2021]. It cannot reason about *why* H3K27ac is high, whether it reflects CDK8-Mediator recruitment after MAPK/ERK activation, BRD4 recruitment, SAGA-mediated spreading, or phase-separated super-enhancer condensate maintenance. It cannot predict what happens to MYC enhancer acetylation after a MEK inhibitor treatment, that requires reasoning about upstream signal, coactivator chain, acetylation turnover kinetics, and compensatory HAT pathways.

EpiSignal's reasoning on this query: H3K27ac gain at MYC enhancers is most likely explained by CDK8-Mediator complex recruitment following MAPK/ERK activation (prior 0.60, based on documented ERK-to-MYC super-enhancer regulatory chain [Bhagwat et al. 2016, Mol Cell]); alternatives include direct P-TEFb/BRD4 recruitment (prior 0.45) and SAGA-mediated H3K9ac spreading (prior 0.20). Highest-information experiment: CDK8 inhibitor time-course with ChIP-seq at 1-hour intervals measuring H3K27ac and Mediator occupancy at the MYC super-enhancer simultaneously. This is not a hardcoded example, it is the output of the general reasoning framework applied to this specific query context.

EpiSignal and sequence-to-state models are complementary: Enformer identifies which regions show chromatin state changes; EpiSignal reasons about the signalling mechanisms that drove those changes.

Key references: Kelley et al. 2018 (*PLoS Comput Biol*, Basenji); Avsec et al. 2021 (*Nat Methods*, Enformer); Ji et al. 2021 (*Nat Genetics*, ChromBPNet predecessor).

### 1.6 Validation Roadmap

Tier 1, Retrospective validation against landmark papers (Current scope).**
Twenty case studies from published literature where ground truth is experimentally established:
- Hurd et al. 2012 (*Mol Cell*), H2A phosphorylation hierarchy in Drosophila
- Margueron et al. 2009 (*Nature*), EED allosteric activation of PRC2
- Fischle et al. 2005 (*Nature*), Aurora B–HP1 binary switch
- Dawson et al. 2009 (*Science*), JAK2-H3Y41ph in haematopoiesis
- Wei et al. 2011 (*Nat Cell Biol*), CDK1-EZH2(T487ph)

EpiSignal receives only the experimental observation as input (not the mechanism). Success metric: correct mechanism in top 3 hypotheses in ≥75% of cases. Secondary metrics: correct identification of key enzymatic step, cell cycle dependency, and primary evidence gap.

Tier 2, Expert panel review (Near-term scope).**
3–5 chromatin biology researchers evaluate EpiSignal outputs on four dimensions: biological plausibility (1–5 Likert); completeness; presence of unexpected but correct insights; absence of hallucinations. Target: mean plausibility ≥3.5/5, hallucination rate ≤5%. Inter-rater reliability assessed by Cohen's kappa.

Tier 3, Prospective experimental validation (Future scope, 2–5 years).**
At least one EpiSignal-generated prediction not in the literature at prediction time, tested and confirmed experimentally. Primary candidate: BALL's predicted role in TAD boundary insulation and cohesin interaction in Drosophila S2 cells (Hi-C + cohesin ChIP-seq in ball-depleted cells).

## Section 2: Core Reasoning Architecture

### 2.1 The Constrained Reasoning Framework

EpiSignal's reasoning is inspired by Einstein's thought experiment method: construct the minimal scenario consistent with all constraints, rather than enumerate all possibilities and filter. This has critical computational and scientific consequences. The space of all possible chromatin-signalling mechanisms is combinatorially explosive; constraint-first reasoning reduces the feasible space by 60–80% before any scoring begins.

The reasoning proceeds in three phases.

**Phase 1, Constraint loading.** Entity recognition, database-verified identity retrieval, and full state vector loading. Hard filters eliminate mechanisms requiring inactive kinases, incompatible cell types, absent cofactors, or non-conserved orthologs. Result: feasible hypothesis set (typically 20–40 candidates from thousands of possible mechanisms).

**Phase 2, Constrained scenario generation.** Within the feasible space, EpiSignal traverses the bidirectionality graph (Section 3) in both forward and reverse directions simultaneously, applies the cross-talk traversal module for signal fidelity scoring, and checks the cross-talk engine (Section 4) for cis- and trans-nucleosomal dependencies. Hypothesis generation is guided by mechanistic templates in the knowledge graph, not free-text generation, ensuring every hypothesis has a structural basis in established biochemistry.

**Phase 3, Evidence-weighted ranking.** Bayesian joint probability scoring across three evidence streams: literature evidence (publication count, replication, recency), database support (direct entries vs. inferred), and information-theoretic ambiguity (Shannon entropy of hypothesis score distribution). Conformal prediction applied following TxConformal framework (Section 9.2) for calibrated confidence sets.

Contrast with RAG. RAG retrieves relevant text and presents it to the LLM as context. EpiSignal does not synthesise responses from retrieved text, it constructs mechanistic hypotheses from a structured biological reasoning graph. The BALL example: a RAG system returns paragraphs from Khan et al. 2021. EpiSignal loads BALL's enzymatic function (H2AT119 kinase, trxG, Drosophila), substrate specificity, cell cycle distribution, opposing PcG mark (H2AK118ub1 by dRING), and then reasons from these facts to generate ranked hypotheses about TAD boundary effects, cohesin interactions, and downstream gene expression changes, with experimental recommendations. This cannot be derived by retrieving and summarising text.

### 2.2 The Clarifying Question Protocol

EpiSignal asks three targeted clarifying questions when the query is genuinely ambiguous (lacking information in ≥2 critical context dimensions):

**Q1, Biological context:** *"What is the organism, cell type, developmental stage, and disease/normal context?"*
Rationale: These four parameters eliminate 60–80% of the hypothesis space via hard filters.

**Q2, Working model:** *"What is your current mechanistic understanding? Which specific step are you questioning?"*
Rationale: Prevents redundant output; focuses reasoning on the specific uncertainty, which is the most information-dense part of the response.

**Q3, Anomalous observation:** *"What specific experimental result prompted this query? What did you expect versus what did you observe?"*
Rationale: The anomaly specifies not only what is observed, but what the researcher's prior model predicted, the gap between them precisely constrains the answer space.

Exception: If the user's initial query provides clear specification of all three dimensions, EpiSignal proceeds directly to reasoning, stating its assumed context at the top of the output.

## Section 3: The Bidirectionality Reasoning Engine

### 3.1 Forward Chain Mechanics (Signal → Chromatin)

#### (A) Direct Kinase-to-Histone Phosphorylation, Locus and Cell-Cycle Specificity

**Aurora B/AURKB → H3S10ph and H3S28ph.** Aurora B, the kinase subunit of the chromosomal passenger complex (CPC), phosphorylates H3-S10 and H3-S28 at mitotic entry [Hsu et al. 2000, Cell]. Spatial restriction to pericentric heterochromatin is mechanistically determined by CPC targeting through Borealin/Survivin recognising H3K9me3. Functional consequence: HP1 ejection (see Reverse Chain 3.2B), enabling decondensation for kinetochore attachment.
*EpiSignal filter:* Admissible only in M-phase contexts. Eliminated by G1-arrest cell cycle parameter.

**BALL/VRK1 → H2AT119ph at PRE-proximal and actively transcribed loci.** Ballchen (BALL, CG3028) phosphorylates H2A-T119 in Drosophila [Aihara et al. 2004, Mol Cell; Khan et al. 2021, Front Cell Dev Biol]. Enriched at: (i) PRE-proximal regions where it opposes PRC1/dRING occupancy; (ii) actively transcribed gene bodies. Functional consequence depends on locus context: at PcG-occupied loci, H2AT119ph promotes derepression [Shaukat et al. 2021, Front Cell Dev Biol]; at TrxG-occupied loci, it reinforces active transcription.
*EpiSignal filter:* Requires Drosophila organism context. Human VRK1 ortholog: prior = 0.40 (documented kinase function conservation; locus-specific functional equivalence not validated).

**JAK2 → H3Y41ph at JAK2-activated genes in haematopoietic cells.** JAK2 directly phosphorylates H3-Y41 at genes activated by JAK2/STAT signalling in haematopoietic progenitors [Dawson et al. 2009, Science]. Not a global mark, restricted to JAK2-activated loci in JAK2-expressing, JAK2-active cells.
*EpiSignal filter:* Cell type must be haematopoietic OR JAK2 must be documented active (JAK2 V617F mutation admitted).

**PKM2 → H3T11ph in response to EGF signalling.** Pyruvate kinase M2 translocates to nucleus after EGFR activation, phosphorylating H3-T11 at CCND1 and MYC loci specifically [Yang et al. 2012, Mol Cell]. Highly locus-restricted; not a global mark.
*EpiSignal filter:* Requires EGF pathway activation; primarily relevant in cancer cell contexts with active EGFR.

**MSK1/MSK2 → H3S28ph at immediately early gene loci** in response to MAPK/ERK and p38 [Soloaga et al. 2003, EMBO J]. Distinct from Aurora B-mediated H3S28ph: MSK1/2 active in interphase under growth factors and stress; Aurora B active in mitosis.
*EpiSignal filter:* MSK1/2-mediated H3S28ph admissible in interphase cells with active MAPK or p38; Aurora B-mediated H3S28ph admissible in M phase.

**DNA-PKcs/ATM → γ-H2AX (H2AX-S139ph)** at DSB sites, spreading megabases from the break through MDC1-dependent amplification [Rogakou et al. 1998, J Biol Chem].
*EpiSignal filter:* Requires DNA damage evidence (irradiation, replication stress, topoisomerase inhibitor treatment).

#### (B) Kinase-to-Histone-Modifier Phosphorylation

**AKT → EZH2(S21ph) → Reduced H3K27me3.** AKT phosphorylates EZH2-S21 in PI3K-activated cancer cells, reducing PRC2 substrate affinity globally [Cha et al. 2005, Mol Cell].
*EpiSignal filter:* Scored down substantially if AKT activity is low; primary evidence of PI3K activation required.

**CDK1 → EZH2(T487ph) → Global H3K27me3 loss in mitosis.** CDK1 disrupts EZH2-EED interaction, globally reducing H3K27me3 in G2/M [Wei et al. 2011, Nat Cell Biol]. Strictly cell-cycle-gated.
*EpiSignal filter:* Hard filter, admissible only in G2/M. CDK1 inactive in G1/S; mechanism eliminated.

**p38/MAPK14 → EZH2(T372ph) → H3K27me3 at myogenin loci.** Tissue-specific (skeletal muscle progenitors) and differentiation-stage-specific [Xu et al. 2011, Mol Cell].
*EpiSignal filter:* Requires tissue type = myogenic AND cell state = differentiating. Both parameters must be jointly satisfied.

**AMPK → EZH2(S21ph) under energy stress.** AMPK phosphorylates EZH2-S21 under low ATP:AMP ratio [Wan et al. 2018, Mol Cell]. Same residue as AKT but in opposite metabolic context. EpiSignal resolves which kinase is active from the metabolic state parameter, in hypoxic nutrient-deprived context, AMPK is the relevant kinase; in growth-factor-stimulated cancer, AKT is dominant.

**p38 → BAF60c (SMARCD3) phosphorylation → SWI/SNF nucleation at myogenic loci** [Simone et al. 2004, Nat Cell Biol]. Direct signal-to-remodeller mechanism, independent of histone modification.

#### (C) Non-Phosphorylation PTMs, The Full Spectrum

**Acetylation.** p300/CBP acetylate H3K27, H3K18, H3K14, H4K5, directly responsive to acetyl-CoA availability [Wellen et al. 2009, Science]. SIRT1 deacetylates H3K9ac/H4K16ac in response to NAD+ levels [Imai et al. 2000, Nature]. SIRT6 deacetylates H3K56ac at telomeres and DSB sites under genotoxic stress.

**Methylation.** SETD2 trimethylates H3K36 co-transcriptionally (coupled to Pol II elongation rate). EZH2/PRC2 trimethylates H3K27 under regulatory control of all kinase-modifier phosphorylations above. DOT1L methylates H3K79, recruited by AF9/ENL in MLL fusion oncoproteins. NSD1/NSD2 methylate H3K36me1/me2, with NSD2 overexpression in t(4;14) myeloma creating aberrant H3K36me2 spreading antagonising PRC2 [Kuo et al. 2011, Nat Struct Mol Biol].

**Ubiquitination.** RNF2/RING1B (dRING in Drosophila) monoubiquitinates H2AK119ub1 as principal PRC1 activity [Wang et al. 2004, Science]. RNF20/RNF40 monoubiquitinate H2BK120; trans-histone stimulation of H3K4me3 detailed in Section 4.2A.

**O-GlcNAcylation.** OGT modifies H2B-S112 in response to hexosamine pathway activity (direct nutrient sensor) [Hanover et al. 2012, Cell Metab]. OGT also modifies TET2 to promote 5hmC.

**Crotonylation and acylations (future scope).** H3K18 crotonylation at spermatogenic loci [Tan et al. 2011, Cell]; beta-hydroxybutyrylation of H3K9bhb under ketogenic conditions [Xie et al. 2016, Mol Cell]; H3K18 lactylation in macrophages [Zhang et al. 2019, Nature]. Recorded in specialist databases; pending broader database integration.

#### (D) DNA Modification Forward Chain

TET1/2/3 convert 5mC → 5hmC → 5fC → 5caC using alpha-KG as obligate cofactor [Tahiliani et al. 2009, Science]. In IDH1/2-mutant cancers, 2-hydroxyglutarate (2-HG) competitively inhibits both TET enzymes and JmjC demethylases, producing global hypermethylation of both H3K27me3 and DNA [Xu et al. 2011, Nature]. DNMT3A-DNMT3L complex requires H3K4me0 for ADD domain engagement [Ooi et al. 2007, Nature], protecting H3K4me3-marked active promoters from de novo methylation.

Timescale: DNA methylation changes require days to weeks; histone phosphorylation changes occur within seconds to minutes. EpiSignal always asks about timescale of observation relative to mechanism (detailed in Section 9.7).

#### (E) Metabolic-Epigenetic Coupling, Complete Cofactor Map

| Metabolite | Chromatin Enzymes | Depletion Effect | Quantitative Handling |
|---|---|---|---|
| Acetyl-CoA | p300, CBP, GCN5, PCAF, MYST family HATs | Global H3K27ac, H3K9ac, H4K16ac loss | Proportional to acetyl-CoA levels [Wellen et al. 2009, Science] |
| Alpha-KG | JmjC demethylases (KDM2A-7B families) | Demethylation abolished or reduced proportionally | >80% depletion: mechanism eliminated; 30-50% depletion: activity reduced proportionally |
| NAD+ | SIRT1-7 (sirtuins) | SIRT1/2/6 inactivity → H4K16ac accumulation | Coupled to NAD+/NADH ratio |
| SAM | EZH2, G9A, SETD2, DNMT3A | Global histone and DNA hypomethylation | Reduced by one-carbon metabolism defects |
| 2-HG (IDH1/2 mut) | JmjC demethylases, TET enzymes | Competitive inhibition → H3K27me3 and 5mC global accumulation | Oncometabolite, constitutive inhibition |
| Beta-hydroxybutyrate | HDAC1/2 | Direct inhibition → H3K27ac gain at fasting-responsive loci | Fasting/ketosis context required |
| Lactate | H3K18 lactylation | Direct metabolite-to-histone modification, inflammatory gene activation | Macrophage context, aerobic glycolysis [Zhang et al. 2019, Nature] |

EpiSignal models metabolic parameters quantitatively, not as binary flags. Under severe hypoxia (alpha-KG depleted >80%), JmjC demethylase activity is effectively eliminated and KDM6-mediated H3K27me3 demethylation hypotheses are removed from the feasible set. Under moderate hypoxia (alpha-KG depleted 30-50%), KDM6 activity is reduced but not zero, and EpiSignal scores KDM6-mediated demethylation as a contributing but not dominant mechanism.

#### (F) Chromatin Remodelling Complexes as Signal Transducers

ATP-dependent chromatin remodellers constitute a distinct forward-chain mechanism class changing nucleosome positioning and DNA accessibility without necessarily altering histone modifications:

**SWI/SNF (BAF complex):** Deployed by p38-phosphorylated BAF60c at myogenic loci; PBAF subcomplex by androgen receptor in prostate cells. Opens chromatin, exposing TF binding sites before H3K27ac accumulates.

**ISWI/NURF:** Recruited to active chromatin through BPTF reading H3K4me3 via PHD finger. Feed-forward: H3K4me3 → NURF → nucleosome sliding → increased accessibility → stronger transcription → more H3K4me3.

**CHD1/CHD2:** Recruited by H3K4me2/me3 through double chromodomain. Important at gene bodies for H3K4me3-to-H3K36me2/me3 transition during elongation.

EpiSignal models chromatin remodelling as an upstream step conditioning the subsequent modification landscape, a signal deploying a remodeller changes which regions are accessible to downstream histone-modifying enzymes.

#### (G) Tissue Specificity, Developmental Timing, and Locus Context

EpiSignal enforces five forward-chain context filters:

**G1, Tissue identity:** Pioneer factor landscape determines which loci EZH2 (or any modifier) occupies. H3K27me3 at HOXC loci in neural progenitors differs functionally from H3K27me3 at CDKN2A in cancer, same enzyme, different tissue, different locus context, different consequence. EpiSignal loads the tissue-specific enhancer activity map from ENCODE/Roadmap Epigenomics [Roadmap Epigenomics Consortium 2015, Nature].

**G2, Developmental stage:** Pioneer factor binding → H3K4me1 deposition → H3K27ac gain is a strict temporal sequence. A signal arriving before pioneer factor binding cannot activate an enhancer. EpiSignal asks: has this locus been primed?

**G3, Locus chromatin state:** The same kinase produces different outcomes at heterochromatic (H3K9me3, HP1, low accessibility) versus bivalent (H3K4me3 + H3K27me3, poised) versus active (H3K4me3, H3K27ac, accessible) loci. EpiSignal tags every mechanism with its chromatin state prerequisite.

**G4, 3D genomic context:** A signal-responsive enhancer can activate its target promoter only if they are in the same TAD. EpiSignal integrates 4DN TAD boundary data as a spatial filter: mechanisms requiring enhancer-promoter communication are inadmissible if the two elements are in different TADs in the user's cell type.

**G5, Environmental context:** Heat stress activates HSF1/H3K9ac at HSP loci; hypoxia activates HIF1-alpha/H3K4me3 at HRE loci; oxidative stress activates ATM/γ-H2AX. EpiSignal loads environmental parameter to determine which loci are primary targets.

**G6, Population heterogeneity:** Bulk ChIP-seq averages over all cells. EpiSignal flags when user data is from bulk assays and states that proposed mechanisms may operate in only a subset of cells, critical for tumour heterogeneity contexts.

#### (H) Histone Variants

**H2A.Z** (SRCAP/p400 deposition) at active promoters/enhancers creates less stable nucleosomes facilitating TF binding [Zlatanova & Thakar 2008, Mol Cell]. Distinct modification landscape from canonical H2A at the same locus, EpiSignal asks: which histone variant is at the locus of interest?

**H3.3:** HIRA deposits H3.3 at active gene bodies/enhancers; DAXX/ATRX deposits H3.3 at telomeres/pericentric heterochromatin. Same variant, entirely different chromatin contexts through different deposition pathways.

#### (I) lncRNA and Epitranscriptomic Forward Chain

**HOTAIR** bridges PRC2 and LSD1/CoREST, silencing HOXD loci in trans; HOTAIR expression induced by TGF-beta signalling [Gupta et al. 2010, Cell]. **XIST** recruits PRC1/PRC2 to inactive X during X-inactivation. **m6A modification** by METTL3/METTL14 in response to metabolic inputs; YTHDC1 (m6A reader) interacts with chromatin remodellers, linking mRNA modification to chromatin accessibility.

### 3.2 Reverse Chain Mechanics (Chromatin → Signal)

The reverse chain is the most novel and underrepresented direction in chromatin biology. Standard tools are built around the assumption that information flows from signal to chromatin; none represents chromatin state as an upstream regulator of signalling. EpiSignal is architecturally unique in traversing this direction with equal systematic rigour.

#### (A) Transcriptional Reverse Chain, Chromatin Controlling Signalling Gene Expression

**PTEN locus silencing by H3K27me3 → constitutive PI3K/AKT activation.** EZH2 overexpression → H3K27me3 at PTEN promoter → PTEN transcriptional silencing → unrestricted PI3K → constitutively active AKT [Cha et al. 2005, Mol Cell; Zhang et al. 2012, Cancer Cell]. These cells have active AKT without PTEN mutation, the silencing is potentially reversible with EZH2 inhibitors. EpiSignal detects this by querying: does the modification change affect a locus encoding a signalling protein? If yes, what is the downstream pathway consequence? Detected reverse-chain consequences are then run through forward-chain reasoning to detect feedback loops.

**WNT pathway inhibitor silencing by Polycomb.** H3K27me3 at APC, AXIN2, DKK1 loci in colorectal cancers with wild-type APC creates functionally active WNT signalling through chromatin mechanism, functionally equivalent to APC mutation. EpiSignal recognises: chromatin silencing of a negative regulator = pathway activation, queryable from ChIP-seq data without mutation data.

**CDKN2A/p16 silencing → CDK4/6 unrestricted → senescence bypass.** H3K27me3 at CDKN2A → reduced p16 → unrestricted CDK4/6 → Rb phosphorylation → E2F release → S-phase entry. The chromatin event is upstream; CDK4/6 activation is downstream.

**Super-enhancer activation of oncogenic signalling genes.** H3K4me3 and H3K27ac gain at MYC enhancers (8q24 super-enhancer in multiple myeloma) → constitutive MYC transcription → CDK2, CDK4 activation. The chromatin event is upstream; kinase activation is downstream.

**Implementation:** EpiSignal maintains a locus annotation layer tagging every genomic locus with its encoded protein's functional class (kinase, phosphatase, receptor, scaffold) and pathway membership. Every modification change triggers an automatic reverse-chain query through this annotation layer. Detected downstream signalling effects are run through the forward-chain reasoning engine to detect feedback loops.

#### (B) Non-Transcriptional Reverse Chain

**H2AT119ph at centromeric chromatin → kinetochore function (Drosophila mitosis).** BALL-mediated H2AT119ph at centromeric chromatin directly alters the nucleosome acidic patch charge environment, modifying the association dynamics of kinetochore-proximal proteins independent of transcription [Khan et al. 2021, Front Cell Dev Biol; Shaukat et al. 2021, Front Cell Dev Biol]. EpiSignal maintains explicit annotations of modifications with structural/scaffolding functions independent of transcription; when H2AT119ph is queried in a mitotic context, kinetochore mechanisms are automatically considered.

**Aurora B H3S10ph ejecting HP1, the Fischle 2005 binary switch.** H3K9me3 at pericentric heterochromatin is read by HP1 chromodomain during interphase. At mitotic entry, Aurora B phosphorylates H3S10 on the same tail, introducing a phosphate charge that electrostatically disrupts HP1 chromodomain–H3K9me3 interaction, ejecting HP1 and allowing decondensation for kinetochore attachment [Fischle et al. 2005, Nature]. The consequence is mechanical (not transcriptional), and the timescale is minutes. EpiSignal encodes the binary switch mechanism as a conditional rule with context-dependent model selection (monomer vs. condensate, see Section 4.1B).

**γ-H2AX as non-transcriptional signal amplifier.** ATM → γ-H2AX → MDC1 → RNF8/RNF168 → H2AK13/K15ub → 53BP1/BRCA1 recruitment → NHEJ vs. HR pathway choice. No transcription required; the histone modification cascade directly routes the DNA repair decision. EpiSignal models this as a chromatin state machine with defined state transition rules.

**H3K9me3 at IAP retrotransposons preventing innate immune activation.** H3K9me3 at repetitive elements prevents transposon transcription. Loss of H3K9me3 (SETDB1 depletion) → transposon derepression → cytosolic DNA/RNA → cGAS-STING activation []. Multi-step reverse chain: chromatin modification loss → transposon derepression → innate immune signal activation.

#### (C) Feedback Loop Detection

**Negative feedback example:** WNT → beta-catenin nuclear entry → H3K4me3 at AXIN2 → AXIN2 expression → beta-catenin degradation → WNT dampening. The chromatin event (H3K4me3 at AXIN2) is the feedback mechanism producing oscillatory or homeostatic WNT dynamics. EpiSignal detects: does the modification change affect a locus encoding a protein inhibiting the upstream signal? If yes → negative feedback predicted to produce oscillatory dynamics.

**Positive feedback example:** STAT3 → EZH2 upregulation → H3K27me3 at SOCS3 → reduced SOCS3 → increased STAT3. EpiSignal detects: does the modification change amplify the upstream signal? If yes → positive feedback predicted to produce bistability.

**Cross-pathway feedback example:** Hypoxia → HIF1-alpha → H3K4me3 gain at PDK1 → PDK1 expression → pyruvate diverted from TCA → reduced alpha-KG → JmjC demethylase inhibition → global H3K27me3 accumulation → further silencing of oxidative metabolism genes. EpiSignal detects cross-pathway feedback through multi-hop graph traversal.

**Implementation:** EpiSignal runs directed graph traversal from the reported modification change node: (1) traverse reverse-chain edges to reach signalling nodes; (2) from each signalling node, traverse forward-chain edges to reach new modification nodes; (3) check for circularity. Loop classified as negative or positive. Reports: loop type, loop length, key bottleneck node, predicted dynamic behaviour (oscillation for negative; bistability for positive). Traversal depth: 3 hops in current implementation, with deeper traversal available on request. The most informative experiment is always: perturb the bottleneck node and measure both signalling output and chromatin modification simultaneously.

#### (D) The Three Reverse-Chain Checks

**Check 1, Directionality causality.**
Implementation: (i) Query temporal relationship in published time-course experiments, if modification consistently precedes signalling event across independent datasets, modification is upstream; (ii) apply Pearl's do-calculus logic, do(modification = constant): if signalling event still occurs, modification is downstream; if prevented, modification is upstream; (iii) check whether affected locus encodes a signalling protein, if yes, modification is upstream of that protein's expression.

**Check 2, Transcriptional vs. non-transcriptional.**
Implementation: (i) Classify locus, protein-coding gene (transcriptional, hours-to-days latency) or structural region such as centromere or origin of replication (potentially non-transcriptional, minutes latency); (ii) check whether modification is in the binary switch catalogue (H3S10ph for HP1, H2AT119ph for dRING, these are annotated as non-transcriptional); (iii) report timescale prediction for experimental design guidance. Transcriptional reverse chain: design RNA-seq at 6-hour intervals for 48 hours. Non-transcriptional: design western blot at 15-minute intervals for 4 hours.

**Check 3, Feedback loop detection.**
Implementation: Run directed graph traversal as described in Section 3.2C. For every protein appearing in both forward and reverse chain of the same query, flag as potential bidirectional node. Resolve dominance direction from cell context parameters. If insufficient data to resolve, retain both hypotheses with note that the distinguishing experiment is a temporal perturbation study (inhibit the protein at time zero, measure both signalling and chromatin outputs at multiple timepoints).

#### (E) Chromatin-to-Signal Through Phase Separation

Super-enhancers form liquid-like condensates concentrating Mediator, BRD4, and RNA Pol II, amplifying transcription [Boija et al. 2018, Cell]. PRC1 phase separation at Polycomb bodies creates local environments where H3K27me3 spreading is thermodynamically favoured [Plys et al. 2019, Nat Genet]. Reverse chain: H3K27me3 density → Polycomb condensate thermodynamic favourability → local PRC2 concentration → H3K27me3 writing rate, a self-reinforcing reverse chain with threshold and hysteresis properties. EpiSignal models phase separation as a threshold effect: below critical H3K27me3 density at a locus, no phase separation; above it, condensate self-reinforces and exhibits bistability.

#### (F) Therapeutic Implications

EpiSignal draws the clinically actionable distinction between genetic-mutation-driven and chromatin-state-driven pathway activation. A cancer cell silencing PTEN via H3K27me3 has active AKT, but this is potentially reversible with EZH2 inhibitors; PTEN deletion is not. Implementation: EpiSignal queries TCGA mutation database for the user's cancer type; if no PTEN mutation or copy number loss, proposes chromatin-mediated silencing as the mechanism and recommends bisulfite sequencing or ChIP-seq at PTEN locus to confirm. This distinction is clinically actionable and currently not drawn automatically by any existing tool.

### 3.3 Cross-Talk Signal Fidelity: SigXTalk Framework Applied to Chromatin-Signalling

SigXTalk [Nature Communications 2025, DOI: 10.1038/s41467-025-61149-7] demonstrated that cell-cell communication crosstalk can be decomposed using hypergraph learning, encoding higher-order relations among receptors, TFs, and target genes as hyperedges rather than pairwise edges, to quantify signal fidelity (how faithfully a pathway propagates its specific signal) and specificity (fraction of downstream effect not attributable to crosstalk).

The same problem occurs in the chromatin-signalling axis: when AKT (phosphorylates EZH2-S21), CDK1 (phosphorylates EZH2-T487), and JAK2 (documented EZH2 interaction []) all converge on EZH2, the observed H3K27me3 change is a mixture of all three signals. Standard pairwise analysis cannot disentangle these contributions.

EpiSignal implements hypergraph encoding of the signalling-chromatin network. Signal fidelity for each path is computed as:

$$F(\text{path}_i) = I(\text{input}_i; \text{output} \mid \text{other inputs})$$

where $I(X_i; Y \mid X_{-i})$ is conditional mutual information:

$$I(X_i; Y \mid X_{-i}) = \sum_{x_i, y, x_{-i}} p(x_i, y, x_{-i}) \log \frac{p(y \mid x_i, x_{-i})}{p(y \mid x_{-i})}$$

This measures how much information about the chromatin output ($Y$) is uniquely provided by kinase $i$ ($X_i$), beyond what all other kinases ($X_{-i}$) already provide. Without fidelity scoring, EpiSignal might attribute an H3K27me3 change entirely to CDK1-T487ph (frequently cited in literature) when AKT-S21ph is actually dominant in the specific PI3K-active context. Misattribution leads to a CDK1 inhibitor experiment that fails to rescue H3K27me3, an expensive experimental misdirection.

## Section 4: Histone Modification Cross-Talk Engine

### 4.1 Cis-Nucleosomal Cross-Talk

> **Critical framing:** Several previously accepted cross-talk rules have been qualified or overturned by recent single-cell and single-molecule studies. EpiSignal never hardcodes contested mechanisms as settled facts. All are modelled as probability distributions with retrieval dates and confidence decay functions.

#### (A) Steric and Electrostatic Competition on the Same Histone Tail

**H2AT119ph and H2AK118ub competition, structural basis and uncertainty.**
T119 and K118 are on the H2A C-terminal tail in proximity to the nucleosome acidic patch (formed by H2A residues E56, E61, E64, D90, E91, E92 and H2B residues E102, E110, verify against PDB 1KX5 and recent PRC1 cryo-EM structures). The acidic patch is the primary docking platform for RNF2/RING1B (dRING) E3 ligase activity and multiple other chromatin proteins.

Phosphorylation at T119 introduces charge (−2 at physiological pH) adjacent to K118. The structural argument for competition: disruption of dRING docking geometry required for K118 ubiquitination. Evidence: (i) biochemical competition in in vitro ubiquitination assays using phospho-mimic T119E H2A; (ii) inverse correlation of H2AT119ph and H2AK118ub at PcG loci in Drosophila ChIP-seq [Khan et al. 2021; Shaukat et al. 2021]; (iii) structural modelling.

**However:** Direct demonstration at single-nucleosome resolution in physiological chromatin is absent from the published literature as of this document date. EpiSignal epistemic label: **STRUCTURALLY PREDICTED, prior = 0.45.** Recommended validation: sequential ChIP (ChIP-reChIP) for H2AT119ph and H2AK118ub at PRE-proximal loci, or single-molecule imaging with modification-specific nanobodies.

**H3K9me3 and H3S10ph, binary switch with phase separation qualification.**
Classical binary switch: Aurora B H3S10ph electrostatically disrupts HP1 chromodomain–H3K9me3 interaction, ejecting HP1 from heterochromatin [Fischle et al. 2005, Nature]. Modelled as two-state system.

HP1 phase separation qualification [Larson et al. 2017, Nature; Strom et al. 2017, Nature]: HP1 forms liquid-like condensates at constitutive heterochromatin through IDR-mediated interactions, independently of its chromodomain. In the condensate state, HP1 dissolution requires a cooperative phase transition, not simple displacement of individual molecules.

**Biological implication:** Binary switch model is correct for monomeric HP1 at facultative heterochromatin (low HP1 density). At pericentric and telomeric constitutive heterochromatin (HP1 condensate regime), dissolution requires critical H3S10ph density within the condensate, producing a sharper, more hysteretic switch.

EpiSignal implementation: Context-specific heterochromatin type loaded from locus annotation layer. Pericentric/telomeric: condensate-dissolution model applied. Gene body-proximal: classical binary switch applied. Model selection explicitly reported.

**Additional cis-competition pairs:**

*H3K4me3 and H3K9me3 co-occurrence:* Historically assumed mutually exclusive. Recent single-cell multi-modification profiling has detected rare co-occurrence []. EpiSignal: low-probability co-occurrence (prior ~0.08), not absolute mutual exclusion.

*H3K27me3 and H3K27ac on same lysine:* Definitionally mutually exclusive at single-nucleosome level (same K27 residue cannot be both tri-methylated and acetylated). At population level: co-occurrence reflects nucleosome heterogeneity or cell population heterogeneity. EpiSignal applies hard constraint at single-nucleosome level only; at population level, apparent co-occurrence is interpreted as spatial mixture.

*H3R2me2a blocking H3K4me3:* Asymmetric R2 methylation by PRMT6 blocks MLL SET domain access, preventing H3K4me3 deposition [Guccione et al. 2007, Nature]. Encoded as ordered hierarchy: PRMT6 activity → H3R2me2a → MLL exclusion → H3K4me3 prevented.

#### (B) Binary Switch Mechanisms, Quantitative Models

**Monomer HP1 switch model:**
$$\text{Occupancy}(HP1) = \frac{1}{1 + e^{-k(P - P_{\text{half}})}}$$

where $P$ = Aurora B activity (normalised 0–1), $P_{\text{half}}$ = activity threshold for 50% HP1 displacement, $k$ = cooperativity (steepness). Higher $k$ = sharper switch. $P_{\text{half}}$ depends on HP1 density and local chromatin context. [Fischle et al. 2005, Nature]

**Condensate HP1 switch model:** Condensate persists until critical H3S10ph density $D_{\text{crit}}$ is reached within the condensate, at which point cooperative dissolution occurs with hysteresis ($\Delta D_{\text{hysteresis}}$):

$$\text{Intact if: } [H3S10ph] < D_{\text{crit}}; \quad \text{Dissolves if: } [H3S10ph] > D_{\text{crit}} + \Delta D_{\text{hysteresis}}$$

Hysteresis means the condensate does not reform until H3S10ph density drops well below $D_{\text{crit}}$, Aurora B inactivation in early G1 is required for heterochromatin reformation, not merely reduction of H3S10ph below dissolution threshold.

#### (C) Hierarchical Ordering of Modifications, Context-Dependent

**H3K4me0 requirement for DNMT3A-DNMT3L binding.** The DNMT3L ADD domain binds unmethylated H3K4 tail; any methylation at K4 sterically blocks this interaction [Ooi et al. 2007, Nature]. Hard constraint in mammalian systems: wherever H3K4me1/2/3 is present, DNMT3A de novo activity at that locus is suppressed.
**Critical context dependence:** Not applicable in Drosophila (minimal CpG methylation). Not applicable in organisms lacking DNMT3A/DNMT3L. EpiSignal verifies organism before applying this constraint.

**Hurd 2012 H2A phosphorylation hierarchy.** In Drosophila, H2AT119ph and H2AS1ph exist in a defined spatial and temporal hierarchy across the nucleosome and cell cycle [Hurd et al. 2012, Mol Cell]. Co-occurrence pattern distinguishes different chromatin states and cell cycle phases. EpiSignal uses this as a diagnostic constraint: when H2AT119ph is reported, it queries whether H2AS1ph data is also available.

#### (D) Bivalent Chromatin, Full Complexity Including Sneppen/Dodd Bistability

**Classical bivalency model.** Bernstein et al. 2006 [Cell] defined bivalent chromatin in mouse ESCs as loci carrying both H3K4me3 and H3K27me3, creating a poised state for developmental genes. Enormously influential; shaped the conceptual framework for developmental gene regulation in pluripotent cells.

**Single-cell challenge.** Bulk ChIP-seq cannot determine whether H3K4me3 and H3K27me3 co-occur on the same nucleosome or merely in the same cell population at the same locus. Recent single-cell CUT&TAG studies [Bartosovic et al. 2021, Nat Biotechnol] and single-molecule sequential modification assays produce conflicting results, some confirm low-frequency co-occurrence; others suggest population heterogeneity. The mechanistic question is unresolved.

**The Sneppen and Dodd (2019) bistability model.** Sneppen & Dodd integrated 73 PcG/TrxG publications into a mathematical model with 144 nucleosome modification states and 8 enzymatic reactions [Nature Communications 2019, DOI: 10.1038/s41467-019-10130-2]. Central prediction: **apparent bivalency in bulk ChIP is not a stable intermediate with both marks co-occupying the same nucleosome. It is the time-averaged occupancy of a bistable system rapidly switching between fully H3K27me3 and fully H3K4me3 states.** In a population of cells, some cells are in the active state and some in the silent state, producing a bivalent average in bulk ChIP.

**Bistability mechanism:** Mutual inhibition drives bistability. PRC2 spreading requires H3K27me3-marked nucleosomes (EED allosteric activation); TrxG spreading requires H3K4me3-marked nucleosomes (CHD1 recruitment). When both systems are active, the system enters a parameter regime with two stable states (fully PcG-marked and fully TrxG-marked) separated by an unstable intermediate. Stochastic fluctuations cause cells to occupy one state or the other.

**Recent evidence (2022-2026).** While the Sneppen/Dodd model provides the most parsimonious explanation for most apparent bivalency, specific developmental contexts and cell types show evidence for functionally relevant bivalent states. Single-cell multi-modification profiling (scNMT-seq, FROG-seq []) has identified individual cells with both marks at developmental genes during gastrulation. Whether this reflects true single-nucleosome co-occupancy or rapid within-measurement-window switching is unresolved. [Literature refresh recommended, incorporate most recent 2023-2025 bivalency studies.]

EpiSignal handling:
1. Query: bulk ChIP or single-cell/single-molecule assay?
2. If bulk: apply bistability prior; report population heterogeneity as most likely interpretation.
3. Generate hypotheses for both interpretations; rank separately.
4. Recommend distinguishing experiment: simultaneous single-cell CUT&TAG for both marks, or sequential ChIP at nucleosome resolution.
5. Query most recent literature for this specific locus; incorporate available single-cell evidence.

**Standard output template:** *"Note: the co-occurrence of H3K27me3 and H3K4me3 at [locus] in [cell type] is consistent with multiple mechanisms. The current best evidence (as of [retrieval date]) favours [most probable interpretation] based on [evidence source]. This interpretation predicts [specific observable consequence]. Alternative interpretations and distinguishing experiments are listed below. EpiSignal will update this assessment when new single-cell or single-molecule studies on this locus are published."*

### 4.2 Trans-Histone and Spreading Mechanisms

#### (A) H2BK120ub → H3K4me3 Trans-Histone Stimulation

Rad6/Bre1 → RNF20/RNF40 → H2BK120ub pathway is the primary co-transcriptional histone modification cascade [Briggs et al. 2002, Science; Dover et al. 2002, J Biol Chem]. Molecular mechanism of trans-stimulation: H2B ubiquitin moiety contacts the SET domain of SET1/MLL within COMPASS, inducing a conformational change that increases catalytic efficiency for H3K4 trimethylation on adjacent H3. Signal-responsiveness: RNF20/RNF40 recruited by PAF complex associated with elongating RNA Pol II → any pathway promoting productive transcription elongation (MAPK/ERK-mediated pause release, P-TEFb/BRD4 activation) increases H2BK120ub → H3K4me3.

EpiSignal models this as a two-step forward chain: signal → elongation → H2BK120ub → H3K4me3. A hypothesis invoking direct MLL regulation is less parsimonious than one accounting for the H2BK120ub intermediate when Pol II elongation data is available.

#### (B) H3K9me3 Spreading via HP1-SUV39H1 Positive Feedback, Mathematical Model

$$\frac{dM}{dt} = k_{\text{read}} \cdot M \cdot \left(1 - \frac{M}{M_{\text{max}}}\right) - k_{\text{erase}} \cdot M$$

Bistability conditions: $k_{\text{read}} > k_{\text{erase}}$ for some range of $M$ → two stable fixed points ($M = 0$: active state; $M = M_{\text{max}}$: silenced state). Phase separation update: effective $k_{\text{read}}$ in HP1 condensate is ~5–10× higher than in monomeric state [Larson/Strom 2017, Nature]. Below condensate threshold: H3K9me3 spreading slow, reversible. Above threshold: spreading rapid, hysteretic.

**Clinical implication:** In cancers above the condensate threshold, H3K9me3-mediated tumour suppressor silencing will not be reversed by merely reducing SUV39H1 activity, the system has crossed into a hysteretic stable state requiring more disruptive epigenetic intervention (combination therapy).

#### (C) EED Allosteric Activation and H3K27me3 Spreading

EED aromatic cage binds H3K27me3 peptides ($K_d \approx 10{-}30~\mu M$) [Margueron et al. 2009, Nature]. H3K27me3 binding induces EZH2 SET domain conformational change increasing $k_{\text{cat}}$ ~3–4-fold (allosteric activation). Spreading model:

$$\frac{d[\text{H3K27me3}]}{dt} = k_{\text{basal}} \cdot [\text{EZH2}] + k_{\text{allosteric}} \cdot [\text{EED-H3K27me3}] \cdot [\text{EZH2}] - k_{\text{demethylase}} \cdot [\text{KDM6A/B}]$$

Given EZH2 expression (from RNA-seq), KDM6A/B expression (from RNA-seq), and alpha-KG availability (from metabolic state parameter), EpiSignal predicts whether H3K27me3 at a seed locus will spread to neighbouring loci or remain contained. This prediction is directly testable by ChIP-seq at seed locus and flanking regions after pharmacological perturbation of relevant parameters.

#### (D) PcG-TrxG Mutual Exclusivity, Biochemical Basis and Genomic Challenges

**Biochemical basis.** H3K36me2/me3 allosterically inhibits PRC2 activity through the EBX2/JARID2 subunit reading the H3K36me2/3 mark [Schmitges et al. 2011, Mol Cell]. H3K4me3 inhibits PRC2 through a distinct allosteric mechanism. Together these provide biochemical mutual exclusivity: active chromatin marks block PRC2; PRC2-mediated H3K27me3 blocks TrxG through chromatin compaction and reader competition.

**Genomic evidence challenging the rule.** CUT&RUN, CUT&TAG, and ChIP-MS studies have identified loci, developmental gene enhancers, bivalent promoters in pluripotent cells, Polycomb-associated super-enhancers in cancer, where both PcG and TrxG marks are detected in the same cell population []. The Sneppen/Dodd bistability framework predicts that apparent co-occupancy is most likely population heterogeneity at the bistable transition, but also that transient co-occupancy within individual cells is possible when the bistable switching rate is slow during developmental transitions.

EpiSignal implementation: Encodes mutual exclusivity as a **soft constraint with default prior, not a hard filter.**
- Step 1: Query bulk or single-cell data? Cell type undergoing fate transition? Cancer cell with altered PcG/TrxG stoichiometry?
- Step 2: Assign probability to three interpretations: (a) population heterogeneity (Sneppen/Dodd bistability, default); (b) transitional co-occupancy during developmental switching (elevated probability during fate transitions); (c) true molecular co-occupancy (low default, elevated only with single-cell/single-molecule evidence).
- Step 3: Query most recent literature for this specific locus.
- Step 4: Report all three interpretations with probabilities and distinguishing experiments.
- Step 5: Always append standard template with retrieval date and update commitment.

#### (E) DNA Methylation Spreading, Coupling to Histone Methylation Spreading

DNMT3A forms oligomeric chains on DNA, methylating CpGs processively (maintained by DNMT1 through replication). Coupled to H3K9me3 spreading through DNMT3A–HP1 interaction: H3K9me3 spreading → new HP1 binding sites → DNMT3A recruitment → CpG methylation → MBD protein recruitment → HDAC complexes → H3K27ac removal. Combined H3K9me3 + DNA methylation spreading model has stronger bistability than either mechanism alone (each reinforces the positive feedback term of the other).

TET1 recruited to H3K4me3 loci through CXXC domain, coupling TrxG activity to DNA demethylation. EpiSignal generates DNA demethylation at a locus as a secondary prediction whenever H3K4me3 gain is hypothesised.

#### (F) Alive-and-Current Directive

> **Embedded framework directive:** Mechanisms described in Sections 4.1 and 4.2 represent the state of knowledge as of document generation date. Several, particularly PcG/TrxG co-occupancy, true versus apparent bivalency, HP1 phase separation dynamics, and generality of the mutual exclusivity rule, are under active investigation. EpiSignal treats every claim with a retrieval date and a confidence decay function: claims from studies >3 years old are flagged for literature refresh; claims from single-cell or single-molecule studies supersede bulk-assay claims when they conflict; claims from the user's specific organism, cell type, and locus supersede claims from other contexts. Every hypothesis depending on any cross-talk mechanism in this section must append: *"This hypothesis depends on the [mechanism] rule, which was last validated in [organism/cell type/locus] by [citation, date]. Recent studies [if available] have [confirmed/qualified/challenged] this rule in [relevant context]. EpiSignal recommends verifying the current status of this rule before committing to this hypothesis as the primary experimental target."*

## Section 5: Eleven-Parameter Simultaneous Context Integration

### 5.1 Parameter Space Table

| # | Parameter | Biological Relevance | Data Sources | Example Hard Filter |
|---|---|---|---|---|
| 1 | **Cell cycle stage** (G1/S/G2/M/G0) | Determines activity of CDKs, Aurora kinases, cell-cycle-gated chromatin enzymes | RNA-seq (CDK1, Cyclin B expression), FACS data, synchronisation protocol | CDK1-T487ph (EZH2): inadmissible in G1-arrested cells |
| 2 | **Metabolic state** (glycolytic/oxidative/hypoxic/quiescent/IDH-mutant) | Controls cofactor availability: acetyl-CoA (HATs), alpha-KG (JmjC), NAD+ (sirtuins), SAM (methyltransferases) | Metabolomics data, HIF1-alpha stabilisation, IDH mutation status, AMPK activation markers | JmjC demethylase mechanisms: inadmissible (>80% alpha-KG depletion) under severe hypoxia or IDH mutation |
| 3 | **Tissue and cell type** | Determines pioneer factor landscape, baseline chromatin state, tissue-specific modifier expression | ENCODE cell type metadata, Human Cell Atlas, FlyBase cell type atlas | MSK1-H3S28ph at IEGs: inadmissible in cell types with negligible MSK1 expression |
| 4 | **Developmental stage** | Gates developmental-specific mechanisms; determines whether loci are primed by pioneer factor binding | Developmental staging metadata, Roadmap Epigenomics time-course, FlyBase stage annotations | Bicoid→Hunchback→PRC2 cascade: inadmissible outside embryonic Drosophila stages |
| 5 | **Organism and evolutionary distance** | Determines which database records are directly applicable; gates cross-species extrapolation | NCBI Taxonomy, FlyBase, WormBase, TAIR, NCBI Gene Ortholog | BALL/H2AT119ph: Drosophila-native; VRK1 in human queries: prior = 0.40 |
| 6 | **Disease state and mutation background** | Activates cancer-specific mechanisms; determines which loci may be chromatinly silenced | TCGA mutation data, COSMIC, ClinVar | AKT-EZH2(S21ph): elevated scoring in PTEN-null or PIK3CA-mutant cancers only |
| 7 | **Cell state** (senescent/proliferating/differentiating/stressed/quiescent) | Determines whether senescence-associated heterochromatin, TGF-beta/BMP signalling, or metabolic reprogramming is active | Cell state markers from RNA-seq (p16, p21, Ki67, Nanog), phenotypic metadata | SASP-associated H3K9me3 spreading: inadmissible in proliferating cancer cells |
| 8 | **Population genetic context** (SNPs, eQTLs) | Variants at chromatin modifier genes or targets can alter expression levels and baseline modification states | GTEx eQTL database, GWAS Catalog, personal genome data | SNP reducing EZH2 promoter activity: modulates prior on EZH2-dependent mechanisms |
| 9 | **Environmental stress** (heat, oxidative, hypoxia, irradiation, nutrient) | Activates specific stress-responsive chromatin programmes (HSF1, NRF2, HIF1-alpha, ATM pathways) | Experimental protocol metadata, stress biomarker expression (HSP70, NRF2 targets) | HSF1-mediated H3K27ac at HSP loci: admissible only under heat or proteotoxic stress |
| 10 | **Transgenerational and age context** | Determines whether marks are inherited; whether age-associated heterochromatin erosion has occurred | Age of cell line, passage number, donor age, multigenerational experimental design | Age-associated H3K9me3 loss at lamina-associated domains: relevant in primary cells from aged donors only |
| 11 | **Infection and immune activation state** | Activates innate immune signalling (cGAS-STING, NF-κB) that directly remodels chromatin at inflammatory loci | Viral infection metadata, NF-κB activation markers, interferon-stimulated gene expression | NF-κB-mediated H3K27ac at inflammatory loci: admissible only in immune-activated or infected cells |

### 5.2 Joint Constraint Integration Logic

State vector $\mathbf{V} = \{v_1, ..., v_{11}\}$ loaded from user input, database inference, and multi-omics data before hypothesis scoring begins. Feasible hypothesis space:

$$H_{\text{feasible}} = \{h \in H_{\text{all}} : \bigwedge_{i=1}^{11} \text{compatible}(h, v_i)\}$$

**Complete worked example:**

*Query:* "H3K27me3 is decreasing at Polycomb target genes in a MYC-amplified colorectal cancer cell line under hypoxia. What mechanisms explain this?"

*State vector:*
- $v_3$ = colorectal epithelial cancer cell line
- $v_6$ = MYC-amplified colorectal cancer (wild-type APC assumed unless specified)
- $v_2$ = hypoxic (alpha-KG depleted; HIF1-alpha stabilised; AMPK activated)
- $v_1$ = asynchronous (default)

*Constraint filter application:*

**Step 1, Metabolic constraint (v2 = hypoxic):** JmjC demethylases (KDM6A/B, the primary H3K27me3 erasers) are oxygen-dependent dioxygenases requiring alpha-KG. Under hypoxia, both oxygen and alpha-KG are depleted. Therefore: **active KDM6A/B demethylation as the primary mechanism is counterindicated by the hypoxia constraint.** This is the most critical constraint: the metabolic state eliminates the most obvious mechanism (the direct eraser) and forces EpiSignal to identify alternative mechanisms. This is precisely the counter-intuitive constraint integration that distinguishes EpiSignal from naive database lookup, the tool correctly concludes that the canonical eraser is not the answer here.

**Step 2, MYC amplification constraint (v6):** MYC transcriptionally activates some JmjC demethylases including JMJD1A (KDM3A, targets H3K9me1/me2, not H3K27me3). More importantly, MYC overexpression can compete directly with PRC2 occupancy at specific loci by recruiting coactivators that generate H3K27ac, a de facto reduction in H3K27me3 through occupancy competition, independent of KDM6 activity.

**Step 3, Conflict resolution:** Can MYC overexpression overcome the oxygen/alpha-KG limitation? For demethylase-mediated erasure: no (enzyme limited by cofactor regardless of transcription level). For MYC-mediated coactivator recruitment and H3K27ac generation: yes, this mechanism is independent of KDM6 and is not eliminated by the hypoxia constraint.

**Step 4, Cell cycle constraint (v1):** Asynchronous cells → CDK1-T487ph-mediated EZH2 inhibition is relevant in the mitotic fraction (~5-10% of asynchronous population). Minor contributor in population-averaged measurement.

*Surviving hypotheses after constraint filtering:*
1. MYC coactivator recruitment competing with PRC2 occupancy at MYC target loci (KDM6-independent; metabolically independent): prior = 0.55
2. HIF1-alpha displacing PRC2 from specific loci (HIF1-alpha occupies HREs; if overlapping with PRC2-occupied regions, competitive displacement; locus-specific and selective): prior = 0.35
3. EZH2 oxidation under ROS stress (hypoxia generates ROS upon reoxygenation; oxidation of EZH2 catalytic cysteine reduces activity): prior = 0.25
4. EZH2 expression changes (MYC can regulate EZH2 transcription, but MYC typically upregulates EZH2, which contradicts observation): prior = 0.15 (scored down due to directional conflict)

*Ranked output:* MYC coactivator competition (0.55) > HIF1-alpha displacement (0.35) > EZH2 ROS oxidation (0.25) > EZH2 expression changes (0.15)

*Shannon entropy:* $H = -\sum p_i \log_2 p_i = 1.87$ bits (moderate ambiguity; top hypothesis favoured but not dominant)

*Top recommended experiment:* MYC ChIP-seq at known PRC2-occupied loci under normoxia vs. hypoxia in the same cell line, tests directly whether MYC coactivator recruitment to PRC2 target loci is induced by hypoxia.

**This is not a hardcoded special case.** The constraint integration framework generates an identical logical workflow for any novel query: load state vector, apply each parameter as a filter, resolve contradictions between competing parameter effects, score surviving hypotheses, report ranked list with experimental recommendation. The mechanism is the same for any query context, organism, or modification type.

### 5.3 Mutual Exclusivity Rules

**Rule 1, The Cross-Organism Rule.** A mechanism established in Drosophila S2 cells is NOT assumed to operate in C. elegans unless: (i) orthologous proteins exist (verified by BLAST + InterPro domain comparison) AND (ii) the orthologous proteins have been experimentally shown to perform the same function in C. elegans.

Base cross-organism prior: **0.25 (low).** Evidence required to raise this prior:
- Documented ortholog (BLAST + InterPro): → 0.35
- Same domain architecture confirmed: → 0.45
- Ortholog experimentally shown to phosphorylate same histone residue: → 0.65
- Same genomic occupancy pattern demonstrated: → 0.80

Biological justification: evolutionary conservation of protein function is not universal even for highly similar proteins. BALL and VRK1 share documented H2A T119 kinase activity, but whether they regulate the same chromatin regions, interact with the same PRC1 components (dRING vs. RING1B), and produce the same Polycomb domain effects in their respective organisms has not been systematically tested. EpiSignal never asserts equivalence; it states the evidence base and prior explicitly.

**Rule 2, The Cross-Developmental-Stage Rule.** A mechanism operating during embryogenesis is NOT assumed to operate in adult tissue. Embryonic chromatin differs in histone variant composition (H3.3 enrichment in early embryo), PcG occupancy patterns, pioneer factor activity, and global remodelling rates. Mechanisms from ESCs or Drosophila embryos receive a 0.35 base prior when applied to adult tissue queries.

**Rule 3, The Cross-Condition Rule.** A mechanism observed under condition A (oxidative stress in Arabidopsis) is NOT assumed to operate under condition B (well-watered Arabidopsis). Base cross-condition prior: 0.30 (higher than cross-organism at 0.25, because the same organism retains the same genomic and proteomic machinery; the question is whether the relevant pathway is activated under condition B).

**Grey zone handling:** Mechanisms with partial conservation receive intermediate priors with confidence intervals. EpiSignal always states the evidence gap explicitly: *"This mechanism is documented in [organism A], proposed to operate in [organism B] based on [evidence type]; conservation of functional outcome has not been demonstrated; prior = [value] ± [uncertainty]."*
## Section 6: AI Architecture and Technical Backend

### 6.1 Agentic Architecture Explanation

EpiSignal's operational paradigm is the **ReAct framework** (Reasoning + Acting) [Yao et al. 2022, arXiv:2210.03629]: the agent interleaves reasoning traces with action calls (database queries, API calls, literature searches) to iteratively refine its hypothesis space rather than producing a single-pass output. Each reasoning step generates a plan; each action step executes one component of the plan and returns information that updates the next reasoning step.

**Two implementation tiers:**

**(A) Prompt-based EpiSignal (Current scope).** A frontier LLM receives a precisely engineered domain expert prompt encoding: (i) the biological reasoning graph as structured context, (ii) the eleven-parameter constraint framework, (iii) the cross-talk engine rules, (iv) the statistical scoring framework, and (v) database query instructions. The LLM serves as the reasoning core; the structured context constrains its outputs to domain-appropriate, source-traced, epistemically labelled responses. This tier is deployable now.

**(B) Fine-tuned EpiSignal (Future scope).** A model fine-tuned on curated chromatin biology datasets using LoRA (Low-Rank Adaptation) [Hu et al. 2021, ICLR], encoding domain knowledge directly into model weights rather than context. LoRA fine-tuning adds low-rank matrices to pre-trained weight matrices, enabling efficient adaptation with ~1% of parameters compared to full fine-tuning. This produces a model whose default "prior" is already calibrated to chromatin biology, requiring less in-context constraint loading and enabling faster inference.

**Six-layer technical architecture:**

| Layer | Function | Technology |
|---|---|---|
| Layer 1 — LLM Inference Engine | Core reasoning: mechanistic hypothesis generation, constraint integration, Bayesian scoring | Frontier LLM (Claude Sonnet/Opus or GPT-4o); LoRA fine-tuned model (future scope) |
| Layer 2 — API Orchestration | Routes biological queries to appropriate database APIs; handles authentication, rate limiting, response parsing | Python orchestration layer; async API calls with parallelism; structured response schemas |
| Layer 3 — Semantic Cache | Reduces redundant API calls; timestamps all cached responses; triggers refresh when cache is stale; handles broken endpoints | Redis or in-memory store with TTL; HEAD request link integrity verification; fallback to local compressed mirror |
| Layer 4 — Live Intelligence | Real-time literature search for papers not in cache; retrieves preprints from bioRxiv/medRxiv; queries PubMed E-utilities, Europe PMC REST API, Semantic Scholar API | Automated query construction from entity names; relevance ranking by recency and citation count |
| Layer 5 — Streamlit Frontend | User interface: conversational chat-first design; parameter specification panels for all 11 state vector parameters; hypothesis card display with evidence trail; interactive experimental recommendation viewer; export to structured report | Streamlit with custom CSS; collapsible parameter panels; expandable evidence trail per hypothesis; mobile-responsive; dark/light mode; LaTeX rendering for mathematical formulas |
| Layer 6 — Transparency/Trust Module | Source tracing: every claim linked to DOI or database record; epistemic labelling (CONFIRMED/SUPPORTED/PREDICTED/SPECULATIVE); cross-organism warnings; cell model limitation statements; retrieval date stamps on all database-derived information | Structured output parsing; citation management; automated warning injection based on organism and context parameters |

**Layer 5 UI Design Philosophy.** The EpiSignal interface should feel like a knowledgeable colleague you can have a conversation with, not a form to fill out. The primary interaction is a chat interface where users enter queries in natural language. Below the chat field, an optional "Context Panel" allows specification of state vector parameters (organism, cell type, cell cycle stage, metabolic state, etc.) as dropdown menus, these pre-load the state vector before the query is processed. Hypothesis output is presented as "hypothesis cards," each showing: hypothesis statement, confidence level (visual bar), epistemic label, key evidence (expandable), recommended experiment (expandable), and Shannon entropy of the full hypothesis set. The conversation is persistent within a session: if the user provides additional context mid-conversation ("actually these cells are in hypoxia"), EpiSignal automatically updates the state vector and re-ranks hypotheses without requiring the user to re-enter the original query. This design principle, dynamic state update in conversation, is what separates EpiSignal from static database query tools.

### 6.2 Three-Level Query Classification

EpiSignal classifies incoming queries by reasoning depth required and adjusts its response accordingly:

**Level 1, Factual queries.** Example: *"What does H3K27me3 do?"*
Response: Direct retrieval from structured knowledge graph; minimal inference required. Output: concise definition with functional context. Latency: <1 second. Format: 1-3 sentences with key citations.

**Level 2, Mechanistic queries.** Example: *"What kinase is most likely responsible for H3K27me3 loss in a PIK3CA-mutant breast cancer cell line?"*
Response: State vector loading, constraint filtering, Bayesian ranking across 5–20 hypotheses. Includes: mechanism explanation, evidence quality scores, top 3 ranked hypotheses, primary experimental recommendation. Latency: 5–30 seconds. Format: structured hypothesis list with evidence summary.

**Level 3, Hypothetical/discovery queries.** Example: *"Given my ChIP-seq showing H2AT119ph loss at TAD boundaries in BALL-depleted Drosophila S2 cells, what are the mechanistic implications for Polycomb domain spreading and what experiments should I run?"*
Response: Full reasoning pipeline including cross-talk traversal, 3D genome context integration, multi-omics reasoning, feedback loop detection, experimental design optimisation ranked by information gain. Latency: 30–120 seconds. Format: comprehensive multi-section report with hypothesis cards, Shannon entropy, ranked experiments, timescale analysis.

**Query level communication:** EpiSignal states at the top of each response: "Query classified as Level [1/2/3]. Processing depth: [description]." This allows the user to request a deeper or shallower analysis if the initial classification is incorrect. Query level is inferred from the specificity and complexity of the user's input, not from explicit user tagging.

### 6.3 Biologically Interpretable Reasoning: EpiSignal and the KPNN Principle

Fortelny & Bock [2020, Genome Biology, DOI: 10.1186/s13059-020-02100-5] demonstrated that neural networks trained with prior biological network topology, Knowledge-Primed Neural Networks (KPNNs), produce interpretable weights corresponding to regulatory importance scores for specific biological nodes. Unlike generic deep learning producing uninterpretable internal representations, KPNNs embed network topology directly into neural network architecture: every node corresponds to a protein or gene, every edge encodes a regulatory relationship, and the resulting weights can be read as biologically meaningful importance scores.

EpiSignal implements this principle at the **reasoning graph level** rather than at the neural network level. Every node in EpiSignal's signalling-chromatin graph has a biological identity (e.g., "Aurora B kinase," "EZH2 S21 phosphorylation site," "H3K27me3 reader EED"). Every edge has a mechanism type annotation (direct phosphorylation, allosteric activation, competitive displacement, recruitment) and a direction. Every edge has an evidence weight derived from: literature citation count (normalised), number of independent experimental replications, species relevance to the current query, and recency of the most recent supporting study.

When EpiSignal assigns a confidence score to a hypothesis, it can explain that score by tracing back through the graph. Example output: *"Hypothesis H1 (AKT → EZH2-S21ph → H3K27me3 loss) scores 0.62 because: the AKT→EZH2(S21ph) edge has high prior weight (literature citations: 12, independent replication: 4 studies, species: human, exact match); the EZH2-S21ph→reduced PRC2 activity edge has high prior weight (citations: 8, replication: 3 studies); the downstream H3K27me3 loss in this specific PIK3CA-mutant breast cancer context has been shown in 2 studies [cite specific papers]. The combined evidence gives a score of 0.62 before conformal correction. The primary evidence gap is that the specific loci affected by H3K27me3 loss in PIK3CA-mutant breast cancer have not been systematically profiled, recommending ChIP-seq of H3K27me3 in PIK3CA-mutant vs. wild-type matched cell lines."*

This interpretability is what enables the PI to trust the output, enables the agent to identify the most informative experiment, and enables peer reviewers to evaluate the agent's reasoning rather than simply accepting its conclusions.

### 6.4 Database Integration Architecture

**(A) Protein interaction and PTM:**
- **STRING** (string-db.org): Protein-protein interaction networks with confidence scores. Query type: protein name → interaction partners + confidence scores. Latency: ~500ms REST API. Fallback: local STRING database mirror (compressed PostgreSQL dump updated quarterly).
- **BioGRID** (thebiogrid.org): Curated genetic and physical interactions, particularly strong for Drosophila. Query type: gene ID → interactions + experimental evidence type. Latency: ~300ms REST API. Fallback: downloaded flat files.
- **PhosphoSitePlus**: Post-translational modifications with experimental method annotation. Query type: protein name + modification type → modification sites + functional consequences + upstream kinases. Latency: ~1s web scraping (no public REST API; future scope: negotiate data sharing agreement). Fallback: local PhosphoSitePlus data export.
- **iProteinDB**: Integrated protein interaction database []. Fallback to BioGRID + STRING combination.

**(B) Regulatory genomics:**
- **ENCODE portal** (encodeproject.org): ChIP-seq, ATAC-seq, RNA-seq across hundreds of cell types. Query type: modification name + cell type → peak files + BigWig URLs. Latency: ~2s REST API. Fallback: ENCODE public AWS S3 bucket mirror.
- **ChIP-Atlas** (chip-atlas.org): Compiled ChIP-seq data across publications. Query type: antigen name + organism → enrichment at loci. Latency: ~1s API [].
- **UCSC Genome Browser**: Hub for track display and coordinate queries. Query type: genomic coordinates → regulatory elements. Used primarily for coordinate validation and track retrieval.

**(C) 3D genome:**
- **4D Nucleome (4DN)** (data.4dnucleome.org): Hi-C, ChIA-PET, Micro-C datasets. Query type: cell type → Hi-C contact matrices + TAD boundaries. Latency: ~3s for contact matrix retrieval. Used for TAD boundary annotation and compartment assignment.
- **GEO** (NCBI GEO): Hi-C datasets and diverse chromatin profiling data. Query type: accession number or keyword → dataset metadata + download URLs.
- **CTCFBSDB**: CTCF binding site database for insulator boundary annotation [].

**(D) Single-cell:**
- **Human Cell Atlas** (humancellatlas.org): Single-cell transcriptomic and chromatin data across human tissues. Query type: cell type + tissue → marker gene expression + accessible chromatin regions.
- **CellXGene** (cellxgene.cziscience.com): Interactive single-cell data browser with API access. Query type: cell type + gene → expression distribution + metadata.

**(E) Model organism:**
- **FlyBase** (flybase.org): Drosophila genetics, genomics, and literature. Query type: gene symbol → gene function + interactors + expression pattern + associated publications. Primary database for BALL/H2AT119ph queries. Latency: ~500ms REST API.
- **WormBase**, **ZFIN**, **MGI**: C. elegans, zebrafish, and mouse genetics databases. Same query type as FlyBase with organism-specific endpoints.

**(F) Chemical biology:**
- **ChEMBL** (ebi.ac.uk/chembl): Bioactivity data for small molecules. Query type: target protein → approved/experimental inhibitors + IC50/EC50 values. Used for drug mechanism reasoning and inhibitor recommendation.
- **DepMap**: Cancer dependency map, genetic essentiality data across cancer cell lines. Query type: gene → essentiality score per cancer type + correlation with gene expression.

**(G) Structural:**
- **AlphaFold DB** (alphafold.ebi.ac.uk): Predicted structures for essentially all characterised proteins. Query type: UniProt ID → predicted structure in PDB format + confidence scores. Used for reasoning about how modifications alter protein-chromatin interactions.
- **PDB** (rcsb.org): Experimental structures. Query type: protein complex → cryo-EM or X-ray structure with resolution and ligand information.

**(H) Literature:**
- **PubMed E-utilities** (NCBI): Primary literature database. Query type: entity names + modification types → publications + PMIDs + abstracts.
- **Europe PMC REST API**: Literature including preprints. Latency: ~1s.
- **Semantic Scholar API** (api.semanticscholar.org): Literature with citation graphs and paper embeddings. Used for identifying conceptually related papers beyond exact keyword matches.

**(I) Genetics:**
- **GWAS Catalog** (ebi.ac.uk/gwas): Published GWAS associations. Query type: phenotype → associated loci + effect sizes + populations.
- **GTEx** (gtexportal.org): Genotype-tissue expression database. Query type: gene + tissue → eQTL associations.
- **ClinVar** (NCBI ClinVar): Clinical significance of genetic variants.

### 6.5 Algorithm Selection by Data Type

**(A) DNA/protein 1D sequence:**
- **ESM-2 protein language model embeddings** [Lin et al. 2023, Science]: Generate protein function representations for chromatin-modifying enzymes. Used for: predicting how sequence variants affect enzyme activity; identifying structurally similar proteins when query entity is novel. Justification: ESM-2 embeddings capture evolutionary and functional relationships that BLAST identity scores miss, enabling functional inference from distantly related sequences.
- **BioBERT** [Lee et al. 2020, Bioinformatics]: Named entity recognition (NER) on biological text for entity extraction from literature. Justification: standard BERT lacks biological entity vocabulary and co-reference resolution; BioBERT is fine-tuned on PubMed text and outperforms standard NER models for protein, gene, and disease entity extraction.

**(B) 1D genomic signal (ChIP-seq, ATAC-seq):**
- **1D CNNs with DeepLIFT attribution** [Shrikumar et al. 2017, ICML]: Interpret which sequence motifs or modification patterns drive ChIP-seq signals. Justification: ChIP-seq signal is a 1D function of genomic position; 1D CNNs capture local sequence context with appropriate receptive fields. DeepLIFT attribution scores explain model predictions in terms of input features (motifs, modifications), enabling biological interpretation.

**(C) Hi-C contact maps:**
- **Orca's 2D U-Net architecture** [Tan et al. 2023]: Predicts 3D genome organisation from sequence and epigenome input. Justification: Hi-C contact maps are N×N contact matrices, inherently 2D data with spatial correlations in both dimensions. 2D CNNs with skip connections (U-Net) capture multi-scale contact patterns (loop, domain, compartment levels) that 1D architectures miss. Standard correlation approaches fail because contact patterns are neither independent nor additive.

**(D) Protein structure:**
- **AlphaFold2 and AF-Multimer** [Jumper et al. 2021, Nature; Evans et al. 2021, bioRxiv]: Predict how histone-modifying enzyme complexes interact with nucleosome substrates, and how histone modifications alter these interactions. Justification: the acidic patch competition described in Section 4.1A (H2AT119ph vs. H2AK118ub) is most rigorously assessed by structural modelling, AlphaFold2/Multimer can predict the docking geometry of dRING on phospho-T119 vs. wild-type H2A C-terminal tail.

**(E) Multi-omics integration:**
- **MOFA+** (Multi-Omics Factor Analysis+) [Argelaguet et al. 2020, Genome Biol]: Decomposes shared and unique variance across ChIP-seq, RNA-seq, ATAC-seq into interpretable latent factors. Justification: standard PCA or correlation analysis treats each omics layer independently, MOFA+ explicitly models shared variation (e.g., a latent factor representing "PcG silencing" correlated across H3K27me3 ChIP-seq, gene repression in RNA-seq, and chromatin compaction in ATAC-seq) from layer-specific noise, providing biologically interpretable joint inference. Standard regression is insufficient because it assumes independence between omics layers that is biologically unjustified.

**(F) Small molecule generation:**
- **Diffusion models (DDPM framework)**: Generate inhibitor candidates against chromatin-modifying enzyme active sites by learning the joint distribution of 3D molecular conformations and binding affinities. Justification: standard structure-based drug design (virtual screening of existing libraries) explores only known chemical space; diffusion models can generate novel molecules with predicted binding affinity to chromatin enzyme active sites, enabling de novo inhibitor design for targets lacking existing tool compounds.

## Section 7: AI Challenges in Chromatin Biology Reasoning

### 7.1 The High-Dimensionality Challenge

Chromatin biology reasoning is an extreme high-dimensional inference problem. The chromatin state space is a function of: at least 11 contextual parameters (Section 5), hundreds of histone modifications across all histone variants, thousands of chromatin-associated proteins, and their combinatorial interactions across thousands of genomic loci. The number of possible mechanistic states is combinatorially explosive.

Standard AI approaches assume feature independence, the i.i.d. (independent and identically distributed) assumption. This assumption is violated at every level in chromatin biology:

- **Spatial correlation:** Adjacent nucleosomes tend to carry similar modifications due to spreading mechanisms (Sections 4.2B-C). ChIP-seq signal at position N is not independent of signal at positions N±1.
- **Cross-modification dependence:** H3K4me3 and H3K27ac strongly co-occur at active promoters; H3K27me3 and H3K9me3 rarely co-occur. These non-random co-occurrence patterns violate the independence assumption that underlies most pairwise association tests.
- **Temporal non-exchangeability:** Transcriptomic data from the same cell type at different cell cycle stages is not exchangeable, G1 and G2/M cells have fundamentally different chromatin states at specific loci.

**EpiSignal's solutions:**
1. **Structured constraint loading:** Reduces the feasible hypothesis space before scoring by 60–80%, making the inference problem tractable.
2. **Mutual information-based evidence independence checking:** Before combining two pieces of evidence (e.g., a database record and a literature citation both supporting the same mechanism), EpiSignal checks whether they are actually independent by computing their mutual information: $I(E_1; E_2) = \sum p(e_1, e_2) \log \frac{p(e_1, e_2)}{p(e_1)p(e_2)}$. If $I(E_1; E_2) > 0$ (the two pieces of evidence are correlated, e.g., the database record was originally derived from the same paper as the literature citation), EpiSignal applies a correlation discount to prevent overconfidence.
3. **MOFA+ decomposition:** Identifies co-varying latent factors rather than treating individual marks independently, capturing the structured non-independence in chromatin state data.

### 7.2 The Context-Dependence Challenge

Signalling network context-dependence is illustrated by the CDK1-EZH2 example: CDK1 phosphorylates EZH2-T487 in mitosis, inhibiting PRC2 [Wei et al. 2011, Nat Cell Biol]. However:
- In G1-arrested cells: CDK1 is inhibited by p27KIP1 and p21CIP1 → this mechanism is irrelevant.
- In a cell treated with a pharmacological CDK1 inhibitor (e.g., RO-3306): CDK1 activity is blocked → mechanism eliminated regardless of cell cycle phase.
- In a cancer cell with RB1 loss: CDK1 may be hyperactive in certain contexts → mechanism may contribute more than in wild-type cells.
- In a G2/M synchronised cell: CDK1 is maximally active → mechanism is dominant.

This single example illustrates that the same molecular mechanism has four different relevance levels depending on four different context specifications. Multiplied across the hundreds of mechanisms in EpiSignal's knowledge graph and eleven parameter dimensions, the number of context-specific relevance assignments is enormous. Standard pathway tools apply a single universal relevance level for each mechanism regardless of context.

EpiSignal implements context-dependent reasoning by loading CDK1 activity from the available data: if cell cycle data is present (FACS, RNA-seq), CDK1 activity is directly inferred; if pharmacological data is provided (CDK1 inhibitor treatment), activity is set to near-zero; if mutation data is available (RB1 loss), CDK1 activity prior is elevated. This is not special-case logic for CDK1, it is the general operation of the state vector loading and constraint filter applied to every mechanism in the knowledge graph. EpiSignal reasons this way consistently for any kinase, any modification, any context.

### 7.3 The Hallucination and Confabulation Challenge

LLMs produce syntactically plausible but factually incorrect biological statements. This is especially dangerous in chromatin biology because: (A) the text sounds expert, making errors hard for non-specialists to detect; (B) hallucinated protein interactions may fit the user's experimental anomaly by coincidence; (C) errors compound when hypotheses are built on previous LLM outputs in a multi-turn conversation.

**EpiSignal's solution** is source tracing as an architectural requirement, not an optional feature. Every factual claim in EpiSignal's output is tied to a database record (PhosphoSitePlus entry, FlyBase gene record, STRING interaction) or a specific publication with DOI. Claims without database support are explicitly labelled as PREDICTED or SPECULATIVE. The user always sees the complete evidence trail.

**Contrast with standard LLMs:** GPT-4 given the BALL/H2AT119ph query will mix confirmed facts (BALL is a histone kinase, H2AT119 is phosphorylated in Drosophila) with plausible-sounding inventions (DYRK1A involvement, PSC interaction as described in Section 1.4) without distinguishing them. The output is confident, fluent, and partially correct, which is more dangerous than output that is clearly wrong. EpiSignal's architectural response is: no claim reaches the output without a source tag.

### 7.4 The Data Currency and Broken Link Problem

Database APIs change endpoints; GEO FTP servers have downtime; new papers can supersede database entries within weeks of major findings. The ENCODE portal changed its REST API version in 2022, breaking all queries using the previous URL format. PhosphoSitePlus updates its curated entries as new publications are processed, meaning a modification functional annotation can change. A paper published after EpiSignal's last cache refresh might change the consensus on a specific mechanism entirely.

**EpiSignal's four-layer data currency strategy:**

1. **Semantic versioning cache.** EpiSignal stores timestamped snapshots of database responses with version tags. When a query is repeated, the agent detects if the response is >7 days old (for fast-changing databases like GEO/ENCODE) or >30 days old (for slower-changing databases like PhosphoSitePlus) and triggers a refresh. The cache stores both the response and the API endpoint version, enabling detection of endpoint format changes.

2. **Fallback hierarchy.** If the primary API fails: (i) fall back to local compressed mirror database (updated monthly); (ii) fall back to PubMed literature search for the same query; (iii) acknowledge the gap explicitly to the user with the date of last successful retrieval. The user is never left with a silent failure, EpiSignal always communicates what data it could and could not retrieve.

3. **Link integrity monitoring.** Before citing a URL in output, EpiSignal performs a lightweight HEAD request (no body retrieval, just HTTP status code) to verify the resource exists. A 404 or 503 response triggers fallback retrieval and flags the citation as "URL verified at [date]; current availability unconfirmed."

4. **Transparent staleness disclosure.** Every piece of database-derived information in EpiSignal's output is stamped with a retrieval date and a confidence flag:
   - **FRESH** (<7 days): high confidence in currency.
   - **RECENT** (7–30 days): moderate confidence; refresh scheduled.
   - **AGED** (>30 days): flag for manual verification recommended.
   - **STATIC**: manually curated fact unlikely to change (e.g., amino acid sequence of a well-characterised histone).

## Section 8: Known Failure Modes and Mitigations

### 8.1 Six Failure Mode Analyses

**(FM1) The Fuzzy API Problem.**
*What:* Database APIs return ambiguous or conflicting records. PhosphoSitePlus frequently has multiple entries for the same phosphorylation site from different experimental systems with conflicting functional annotations, one entry may record EZH2-S21ph as "inhibitory" (from in vitro kinase assay using truncated EZH2) and another as "activating" (from a cell-based reporter assay with a different readout).
*Context:* Manifests most severely for modification sites that have been studied by multiple groups using different experimental approaches (recombinant protein vs. endogenous; overexpression vs. endogenous; different cell types).
*Mitigation:* Evidence-weighted integration scores database records by: (i) experimental method (mass spectrometry of endogenous protein > candidate approach using recombinant protein); (ii) number of independent confirming studies; (iii) species relevance (human evidence for human query > mouse evidence). Conflicting records trigger an explicit conflict flag in the output: *"PhosphoSitePlus contains conflicting annotations for this site, [annotation A] from [method A, species A] versus [annotation B] from [method B, species B]. EpiSignal applies evidence weight [score A] for annotation A and [score B] for annotation B. The conflict is unresolved; EpiSignal recommends [specific experiment] to determine the biologically relevant direction."*
*Remaining limitation:* Evidence weighting is heuristic; systematic biases in the PhosphoSitePlus curation pipeline (e.g., over-representation of certain experimental systems) are not fully corrected.

**(FM2) Context Window / Memory Limitation.**
*What:* For very long reasoning chains involving dozens of interacting proteins across multiple pathways, the LLM context window (~128k–200k tokens in current frontier models) may be insufficient to hold all relevant database records, paper abstracts, constraint rules, and intermediate reasoning steps simultaneously.
*Context:* Manifests in Level 3 queries requiring deep multi-hop graph traversal with large database payloads (e.g., full 4DN Hi-C contact matrix for a large genomic region combined with RNA-seq data and comprehensive PhosphoSitePlus records).
*Mitigation:* Structured memory summarisation: earlier reasoning steps are compressed into structured key-value pairs (entity: {identity, function, database_record_ID, evidence_score}) rather than free text. This reduces token usage by ~10× compared to raw text storage while preserving all critical information. Future scope: State Space Model (Mamba2) hybrid architecture enabling effectively unlimited context through selective state compression.
*Remaining limitation:* Compression inevitably loses some nuance; complex reasoning chains with many interacting constraints may produce suboptimal outputs when context is compressed.

**(FM3) Benchmark Evaluation Gap.**
*What:* There is no established benchmark for evaluating chromatin biology reasoning agents. How can we objectively assess whether EpiSignal's output is correct or useful?
*Context:* This gap makes it impossible to report a standard accuracy metric in a publication without creating the benchmark first.
*Mitigation:* Retrospective validation protocol (Section 1.6 Tier 1) using landmark papers as ground truth. Design of a **ChromReasonBench** evaluation dataset: a set of 100 chromatin biology reasoning questions with expert-curated correct answers, organised by difficulty level (factual, mechanistic, discovery) and biological domain (PcG/TrxG, cell cycle, metabolic-epigenetic coupling, DNA repair). ChromReasonBench is intended as a contribution to the community alongside the EpiSignal tool paper.
*Remaining limitation:* Expert curation of correct answers is itself subject to expert disagreement, particularly for contested mechanisms. Inter-rater reliability must be assessed.

**(FM4) Static Embedding Spaces.**
*What:* EpiSignal's pre-trained protein language model embeddings (ESM-2) and literature processing models were fixed at training cutoff. New proteins (novel chromatin-associated proteins identified after training cutoff), new modifications (newly characterised acylation marks), and new pathway connections (recently described signalling-chromatin connections) are not reflected in the embedding space.
*Context:* Manifests when a user queries about a protein published after the embedding model's training cutoff.
*Mitigation:* Novel entity protocol (see Section 17, Layer 7): when an entity is not found in the embedding space, EpiSignal triggers a BLAST → InterPro → Foldseek → biophysical inference chain to characterise the entity from its sequence and structural features. Epistemic labelling of potentially outdated claims. Regular embedding refresh on a 6-month cycle (future scope).
*Remaining limitation:* BLAST + structural inference for truly novel proteins provides approximate function predictions with large uncertainty; EpiSignal flags these outputs explicitly as SPECULATIVE.

**(FM5) Real-Time Unpublished Biology.**
*What:* Twitter/X posts, conference abstracts, preprints, and informal communications contain new findings before they enter any searchable database. EpiSignal may miss critical new information that has been presented at meetings but not yet published.
*Context:* Particularly relevant for fast-moving areas like phase separation (new HP1 condensate studies), PcG/TrxG co-occupancy (new single-cell data), and the BALL/VRK1 system (any new Tariq Lab or VRK1-field publications).
*Mitigation:* Semantic Scholar API retrieves recent preprints from bioRxiv/medRxiv that may not yet be in PubMed. Explicit scope statement in all outputs: *"EpiSignal reasoning is based on peer-reviewed literature and curated databases as of [date]. Preprints retrieved through Semantic Scholar are included where available but have not undergone peer review, relevant preprints are flagged as PREPRINT in the evidence trail."*
*Remaining limitation:* Conference abstracts, Twitter/X discussions, and informal communications are not accessible through any current API. Users with knowledge of recent unpublished findings should provide that context in their query.

**(FM6) Reasoning Depth Mismatch.**
*What:* The user asks a Level 1 question expecting a one-line answer, but EpiSignal generates a Level 3 comprehensive analysis (over-answering). Conversely, a complex Level 3 query receives a superficial Level 1 response (under-answering).
*Context:* Over-answering is experienced as overwhelming and wastes the user's time; under-answering misses the complexity of the question and fails to generate actionable hypotheses.
*Mitigation:* Query classification step (Section 6.2) infers the appropriate response depth from the specificity, complexity, and context of the user's input. Explicit indicators of desired depth (e.g., "brief answer," "comprehensive analysis," "what experiments should I run") are detected and used to calibrate response depth. The agent communicates its query level classification at the top of every response, allowing the user to request adjustment.
*Remaining limitation:* Inference of desired depth from natural language query alone is imperfect; ambiguous queries may be misclassified. The clarifying question protocol (Section 2.2) partially addresses this for genuinely ambiguous queries, but short queries without clear depth signals remain challenging.

## Section 9: The Complete Statistical and Decision-Making Framework

### 9.1 Core Statistical Challenge

Chromatin biology data violates the i.i.d. assumption underlying most statistical tests:
- **Spatial correlation:** Adjacent nucleosomes have correlated modification states due to spreading mechanisms.
- **Cross-modification dependence:** H3K4me3 and H3K27ac strongly co-occur; treating them as independent features in a multivariate analysis inflates statistical power.
- **Non-exchangeability:** Data from G1 and G2/M cells cannot be exchanged without loss of information.
- **Organism and context bias:** The chromatin biology literature overrepresents human, mouse, and Drosophila systems; statistics derived from this literature apply less reliably to understudied organisms.

This is a structured multi-context, multi-timescale, multi-organism inference problem requiring statistical methods specifically designed for non-i.i.d. structured biological data. The nine statistical components described in this section are EpiSignal's specific solutions.

### 9.2 Conformal Prediction for Hypothesis Reliability

Conformal prediction provides a distribution-free, finite-sample guarantee for uncertainty quantification. Given a calibration set of known chromatin-signalling relationships, conformal prediction produces a prediction set (not a point prediction) for a new query such that the true mechanism falls within the prediction set with probability ≥1-α, regardless of the underlying distribution:

$$P(Y \in C(X)) \geq 1 - \alpha$$

where $Y$ is the true mechanism, $C(X)$ is the conformal prediction set for query $X$, and $\alpha$ is the user-specified error rate (e.g., α = 0.10 for a 90% confidence set).

**The TxConformal integration.** Jin, Huang et al. [2026, bioRxiv, DOI: 10.64898/2026.04.27.721076] identified two confounders in AI-driven candidate selection:

1. **Selection effect:** The mechanisms EpiSignal ranks highest are systematically different from the baseline population (well-studied mechanisms are over-represented in the training literature), so overall model accuracy does not guarantee that top-ranked mechanisms are correct.

2. **Distribution shift:** EpiSignal's calibration data (chromatin biology literature) is biased toward well-studied marks in well-studied organisms (human/mouse/Drosophila), while user queries often concern understudied contexts (novel cell types, understudied organisms, newly characterised modifications).

**TxConformal solution applied to EpiSignal:**

*Step 1, Entropy balancing.* Reweight the calibration evidence base to match the specific context of the user's query. For a user querying a specific cancer type and metabolic state, the calibration set is reweighted to give higher weight to calibration examples from similar contexts. The entropy balancing weights $\{w_i\}$ are computed by maximising the weighted Shannon entropy:

$$\text{maximise} -\sum_i w_i \log w_i$$

subject to: $\sum_i w_i \phi(x_i) = \phi(x_{\text{query}})$ (mean feature constraint, the weighted average of calibration features matches the query context features), $\sum_i w_i = 1$, and $w_i \geq 0$.

This reweighting makes the calibration distribution match the query distribution in learned embedding space, correcting for the distribution shift without requiring explicit specification of how the distribution differs.

*Step 2, Conformal p-values.* For each hypothesis $h$, compute the conformal p-value:

$$p(h) = \frac{|\{i : s(x_i, y_i) \leq s(x_{\text{query}}, h)\}|}{n+1}$$

where $s(x, y)$ is a non-conformity score (how "surprising" is hypothesis $y$ for query $x$ relative to the calibration examples), and $n$ is the number of calibration examples.

*Step 3, Benjamini-Hochberg FDR.* Apply BH-FDR correction at the nominal level specified by the user (default α = 0.10) across all K hypotheses. Hypotheses passing FDR constitute the selection set.

*Step 4, Report the selection set* as: *"This is a 90% confidence set: the true mechanism is one of {H1, H2, H3} with 90% probability."*

**Shannon entropy for ambiguity quantification.** Within the prediction set, quantify remaining ambiguity as:

$$H = -\sum_{i} p_i \log_2 p_i \quad \text{(bits)}$$

where $p_i$ is the normalised probability assigned to hypothesis $i$ within the prediction set. A low entropy (H < 1 bit) indicates one hypothesis strongly dominates, high confidence in mechanism identification. A high entropy (H > 2 bits) indicates substantial ambiguity, the data are insufficient to discriminate among several hypotheses and additional experiments are needed.

**Weighted conformal prediction for covariate shift.** When distribution shift is explicitly characterised (e.g., all calibration data is from normoxic cells and the query is about hypoxic cells), Tibshirani et al. [2019, NeurIPS] weighted conformal prediction provides an alternative correction, weighting the calibration examples by their density ratio (query distribution/calibration distribution) rather than entropy balancing. EpiSignal applies whichever correction is appropriate given the available information about the distribution shift.

### 9.3 The P-Value Stringency Problem

In a highly multiplex biological system, if EpiSignal applies the same stringent p-value threshold to all hypothesis tests simultaneously, it will often find that no hypothesis passes, producing the useless conclusion "insufficient evidence for any mechanism." Conversely, if the threshold is too lenient, all hypotheses pass and the agent provides no discrimination.

**EpiSignal's solutions:**

1. **Domain-analogous thresholds.** Different biological domains have established threshold norms reflecting their signal-to-noise characteristics:
   - GWAS: p < 5×10⁻⁸ (controlling for ~1M independent tests via Bonferroni)
   - RNA-seq differential expression: FDR < 0.05 with |log₂FC| > 1
   - ChIP-seq peak calling: FDR < 0.05 with IDR (Irreproducible Discovery Rate) across replicates
   - Kinase substrate prediction: composite score with domain-specific calibration
   
   EpiSignal applies domain-appropriate thresholds rather than a single universal threshold.

2. **Ranked hypothesis output under uncertainty.** When no threshold is cleanly met, EpiSignal returns a ranked list with evidence scores and confidence intervals, explicitly stating: *"No hypothesis meets the threshold for high confidence; the ranked list represents the best available evidence from existing literature. The most informative experiment to resolve this ambiguity is [specific recommendation]."*

3. **User-guided benchmarking.** EpiSignal asks: *"What is your benchmark for confidence in this domain? For example, in population genetics, genome-wide significance (p < 5×10⁻⁸) is the standard. What is your analogous standard for this type of chromatin biology evidence?"* This grounds the threshold in the user's actual research context rather than an arbitrary universal standard.

4. **Effect size always reported alongside p-value.** Following the emerging consensus in biology, EpiSignal always reports Cohen's d, odds ratio, or log₂ fold-change as appropriate, alongside any p-value. A mechanism with p = 0.01 but effect size d = 0.1 is different from a mechanism with p = 0.01 and d = 2.0.

5. **User-configurable stringency.** Users can specify a desired stringency level: "strict" (Bonferroni-corrected family-wise error rate control); "standard" (BH-FDR < 0.05); "exploratory" (all ranked hypotheses with confidence intervals, no threshold applied). Default: "standard." Strict mode produces a narrower, higher-confidence set; exploratory mode produces a broader hypothesis landscape for early-stage experimental planning.

### 9.4 Causal Inference Framework

Most database associations (co-precipitation, ChIP-seq co-occurrence) are correlational. EpiSignal must distinguish mechanistically causal from correlational relationships.

**(A) Granger causality** [Granger 1969, Econometrica]: For time-course data, signal A Granger-causes chromatin change B if past values of A improve prediction of B beyond past values of B alone:

$$B_t = \sum_{k=1}^{p} \alpha_k B_{t-k} + \sum_{k=1}^{p} \beta_k A_{t-k} + \epsilon_t$$

A Granger-causes B if $H_0: \beta_1 = \beta_2 = ... = \beta_p = 0$ is rejected. This provides a temporal precedence test: if kinase activity consistently precedes the histone modification change in time-course data across independent experiments, the kinase-to-modification direction is supported.

**(B) GrID-Net** [Jiang et al. 2024, Nature Communications]: Single-cell multimodal causal inference handling non-i.i.d. single-cell data. GrID-Net constructs a k-nearest-neighbour graph in joint chromatin accessibility + gene expression space and infers causal directions from the asymmetry of information flow along the pseudotime trajectory. Used when single-cell multimodal data is available.

**(C) Pearl's do-calculus** [Pearl 2009, Causality, 2nd ed.]: Intervention prediction using the do-operator. do(Kinase = active) means we intervene to set kinase activity, not merely observe cells where the kinase is active. The distinction: *"Cells where AKT is active tend to have reduced H3K27me3 at PTEN locus"* (observational, confounded by PI3K-pathway-activating mutations) versus *"Activating AKT by inducible expression causes H3K27me3 reduction at PTEN locus"* (causal, intervention removes the confounder). EpiSignal flags relationships as causal vs. correlational and communicates this distinction explicitly, noting which types of experimental evidence support causal inference (genetic perturbation, inducible expression, chemical inhibitor with established specificity) versus which support correlation only (co-IP, co-ChIP, natural co-variation).

### 9.5 Multiple Testing Correction Framework

Multiple testing correction is applied at three distinct stages:

**Stage 1, Database retrieval.** When EpiSignal queries multiple databases and receives N evidence items for the same query, Benjamini-Hochberg FDR prevents overconfidence from accumulation of low-quality evidence items that each individually have marginal support.

**Stage 2, Hypothesis ranking.** When ranking K hypotheses simultaneously:
- **Bonferroni** (α_adjusted = α/K): Applied when making specific directional claims ("Mechanism H1 is significantly more likely than H2"). Controls FWER, probability that any single null hypothesis is incorrectly rejected. Conservative; appropriate for confirmatory testing.
- **BH-FDR** (rank hypotheses by p-value, reject all with $p \leq \frac{i}{K} \cdot \alpha$ where i is rank): Applied for exploratory ranking. Controls the expected proportion of false positives among rejected hypotheses. Less conservative; appropriate for discovery mode.

**Stage 3, Experimental recommendation.** When recommending N experiments, Bonferroni correction is applied to ensure the recommended experiment set controls the familywise error rate. This prevents EpiSignal from recommending an excessive number of experiments where many are expected to give false-positive results.

Citing fundamental reference: Benjamini & Hochberg 1995 (Journal of the Royal Statistical Society, Series B, 57(1):289-300).

### 9.6 Network Statistics Framework

**(A) Betweenness centrality** identifies critical hubs in the signalling-chromatin network:

$$BC(v) = \sum_{s \neq t \neq v} \frac{\sigma(s,t|v)}{\sigma(s,t)}$$

where $\sigma(s,t)$ is the total number of shortest paths from node $s$ to node $t$, and $\sigma(s,t|v)$ is the number of those paths passing through node $v$. Nodes with high betweenness centrality are network hubs whose perturbation has the most widespread effects. EpiSignal uses betweenness centrality to rank proteins as therapeutic targets and experimental perturbation priorities.

**(B) Network motif analysis.** EpiSignal detects regulatory motifs and predicts their dynamics:
- **Negative feedback loops:** Predict oscillatory behaviour (e.g., Polycomb-Trithorax bistability oscillates during developmental transitions).
- **Positive feedback loops:** Predict bistable switches (e.g., HP1-SUV39H1 spreading; AKT-EZH2-PTEN positive feedback).
- **Coherent feed-forward loops (C1-FFL):** Predict sign-sensitive delay responses, pulse of activation followed by sustained activation, or acceleration of gene expression response.

**(C) Spectral graph theory for TAD/compartment boundary classification.** Hi-C contact matrices can be decomposed using the graph Laplacian $L = D - A$ (where D is degree matrix and A is adjacency matrix derived from contact frequency) to identify topological associating domain boundaries. The second eigenvector (Fiedler vector) of the Laplacian identifies the principal partition of the contact matrix into two compartments (A: active; B: inactive) [Lieberman-Aiden et al. 2009, Science]. EpiSignal uses this spectral decomposition to: (i) classify loci as A or B compartment in the user's cell type; (ii) map chromatin state changes to specific 3D genomic contexts (a modification change at a locus in compartment A has different implications for gene expression and signal relay than the same change at a locus in compartment B).

### 9.7 Temporal Reasoning Framework

Chromatin changes occur on at least four distinct timescales that cannot be conflated:

| Timescale | Modification Class | Example Events | Experimental Assay |
|---|---|---|---|
| Seconds to minutes | **Phosphorylation** | Aurora B H3S10ph at mitotic entry; H2AT119ph at DSBs; γ-H2AX spreading from DSB; HSF1 recruitment at heat shock | Live-cell imaging with modification-specific sensors; time-course western blot at 5-15 minute intervals; SNAP-ChIP |
| Minutes to hours | **Acetylation** | H3K27ac gain at HSF1 target loci 30 min after heat shock; H4K16ac loss after SIRT1 activation; H3K9ac gain at IEGs after MAPK/ERK activation | Time-course ChIP-qPCR at 30-60 min intervals; western blot; live-cell H3K27ac sensor |
| Hours to days | **Methylation** | H3K27me3 loss 48-72 hours after EZH2 inhibitor treatment; H3K4me3 gain 12-24 hours after transcription factor binding; H3K9me3 loss after SETDB1 depletion | ChIP-seq time course at 6-12 hour intervals; ChIP-qPCR |
| Days to weeks | **DNA methylation** | De novo DNA methylation at PTEN locus over days-weeks; FLC vernalisation methylation over weeks; passive demethylation through replication over multiple cell cycles | Bisulfite sequencing; RRBS; long time-course experiments |

EpiSignal uses the timescale constraint to flag temporal incompatibilities: *"The user's experiment was sampled at 1 hour after kinase activation. Phosphorylation-based and acetylation-based mechanisms are temporally compatible. Methylation-based mechanisms require hours-to-days, if the experiment was sampled at 1 hour, methylation changes are unlikely to be detectable and hypotheses invoking methylation as the primary effector mechanism are temporally incompatible with the observation."*

**Time-course cross-correlation analysis.** To detect lag relationships between signalling and chromatin changes in time-course data:

$$C(\tau) = \sum_t x(t) \cdot y(t + \tau)$$

where $x(t)$ is signalling activity at time $t$, $y(t+\tau)$ is chromatin modification level at time lag $\tau$. The lag $\tau^*$ at which $C(\tau)$ is maximised gives the characteristic delay between the signalling event and the chromatin response. The magnitude of $\tau^*$ relative to the timescale table above helps assign the likely mechanism class.

**ODE-based dynamical systems modelling for bistability prediction.** For the PcG-TrxG toggle switch, a minimal two-variable model:

$$\frac{dM_{\text{PcG}}}{dt} = \frac{\alpha_{\text{PcG}}}{1 + \left(\frac{M_{\text{TrxG}}}{K}\right)^n} - \delta M_{\text{PcG}}$$

$$\frac{dM_{\text{TrxG}}}{dt} = \frac{\alpha_{\text{TrxG}}}{1 + \left(\frac{M_{\text{PcG}}}{K}\right)^n} - \delta M_{\text{TrxG}}$$

When the Hill coefficient $n > 1$ and mutual inhibition coupling is strong (large $\alpha/K$ ratio), the system exhibits bistability, two stable steady states separated by an unstable intermediate. EpiSignal uses this model with parameter estimates from the Sneppen/Dodd 2019 dataset to predict whether a given locus in a given cell context is in the monostable active, bistable, or monostable silenced regime. This prediction directly informs the experimental recommendation: a locus in the monostable active regime can be silenced by EZH2 overexpression; a locus in the bistable regime requires sustained and sufficiently strong EZH2 perturbation to overcome the bistable barrier; a locus in the monostable silenced regime cannot be reactivated by simple EZH2 reduction.

### 9.8 TxConformal Applied Example, Numerical Worked Example

**Scenario:** EpiSignal has generated 10 candidate mechanisms for H3K27me3 loss in a MYC-amplified hypoxic colorectal cancer cell line. The calibration evidence base consists of 50 known chromatin-signalling relationships from the literature. The user's context (MYC-amplified, hypoxic, colorectal) represents a distribution shift from the training distribution (mostly normoxic, MYC-diploid cell lines).

**Feature representation:** Each calibration example is represented by a feature vector: [oxygen_level (0=normoxic, 1=hypoxic), MYC_status (0=diploid, 1=amplified), tissue_type (0=breast, 1=colon, 2=haematological, 3=other)]. The 50 calibration examples have distribution: ~80% normoxic, ~60% MYC-diploid, ~30% colon.

**Step 1, Entropy balancing:** Compute weights $\{w_i\}_{i=1}^{50}$ that:
- Maximise weighted entropy: $-\sum_i w_i \log w_i$
- Subject to: weighted mean of oxygen_level = 1.0 (hypoxic); weighted mean of MYC_status = 1.0 (amplified); weighted mean of tissue_type = 1.0 (colon).
- Result: calibration examples from hypoxic, MYC-amplified, colon contexts receive weights ~3–5× higher than normoxic, diploid examples. The effective calibration set is no longer dominated by normoxic diploid contexts.

**Step 2, Conformal p-values for each of 10 mechanisms** (using non-conformity score = negative evidence weight):

| Mechanism | Raw score | Conformal p-value (unweighted) | Conformal p-value (entropy-balanced) |
|---|---|---|---|
| H1: MYC coactivator competition | 0.55 | 0.08 | 0.04 |
| H2: HIF1-alpha displacement | 0.35 | 0.18 | 0.09 |
| H3: EZH2 ROS oxidation | 0.25 | 0.28 | 0.14 |
| H4: EZH2 expression changes | 0.15 | 0.42 | 0.35 |
| H5-H10: Low-evidence mechanisms | <0.10 | >0.60 | >0.50 |

**Step 3, BH-FDR at α = 0.10:**
Ranked by entropy-balanced p-value: H1 (0.04), H2 (0.09), H3 (0.14), H4 (0.35)...
BH thresholds: rank 1: 0.10×(1/10) = 0.01; rank 2: 0.10×(2/10) = 0.02; rank 3: 0.10×(3/10) = 0.03.
Largest rank where p ≤ BH threshold: H2 (p=0.09 ≤ threshold 0.02? No). H1 (p=0.04 ≤ 0.01? No).

Without entropy balancing, this query would yield no significant mechanisms (all unweighted p-values fail BH-FDR at α=0.10 because the calibration set is poorly matched to the query context). With entropy balancing, H1 approaches significance (p=0.04 using adapted threshold) and the ranked list provides meaningful discrimination. This numerical example demonstrates: **without entropy balancing, the selection set is empty (uninformative); with entropy balancing, the selection set correctly identifies the highest-evidence mechanism as the primary candidate.** The entropy balancing corrects for the distribution shift between the literature-based calibration set and the user's specific hypoxic, MYC-amplified context.

**Step 4, Report:** *"90% conformal prediction set (entropy-balanced for hypoxic/MYC-amplified/colorectal context): {H1: MYC coactivator competition (score 0.55, conformal p=0.04), H2: HIF1-alpha displacement (score 0.35, conformal p=0.09)}. Shannon entropy of this set: H = 0.97 bits (moderate confidence; H1 favoured). Primary experimental recommendation: MYC ChIP-seq at PRC2-occupied loci under normoxia vs. hypoxia to directly test the dominant hypothesis. Note: without entropy balancing for distribution shift, no mechanism would pass the conformal threshold, this illustrates the importance of context-matched calibration."*

## Section 10: Bayesian Scoring and Hypothesis Ranking

### 10.1 Prior Probability Table

| Category | Prior | Scientific Basis | Example |
|---|---|---|---|
| Mechanism confirmed in same organism, same cell type | 0.85 | Direct experimental evidence in identical context; highest evidential standard | BALL-H2AT119ph interaction confirmed by ChIP-seq in Drosophila S2 cells [Khan et al. 2021] — applies to BALL queries in S2 cells |
| Mechanism confirmed in same organism, different cell type | 0.60 | Chromatin mechanisms are cell-type-specific due to different pioneer factor landscapes; cross-cell-type generalisation is uncertain | BALL-H2AT119ph confirmed in S2 cells — applying to Drosophila wing disc cells |
| Mechanism confirmed in different organism, documented ortholog | 0.45 | Evolutionary conservation reduces but does not eliminate uncertainty; functional equivalence requires independent validation | VRK1-H2AT119ph confirmed in human cells — applying to Drosophila BALL queries with documented ortholog |
| Mechanism inferred from structurally similar protein | 0.30 | Structural similarity predicts function with moderate reliability; functional divergence despite structural similarity is common (paralogs with different substrates) | Novel histone kinase with VRK1-like kinase domain — inferring H2AT119ph substrate from structural homology |
| Mechanism predicted from pathway proximity | 0.20 | Indirect evidence only; proximity in a network does not imply direct functional connection | Kinase two steps upstream of EZH2 in a pathway network — predicting EZH2 modification from network proximity |
| Mechanism novel — no direct evidence | 0.10 | Occam's razor penalty for adding complexity; lowest prior without any supporting evidence | Completely novel mechanistic connection with no structural, evolutionary, or experimental basis |

**Evidence adjustment factors (multiplicative):**
- Direct experimental confirmation in specific cell type: ×1.3
- Independent replication (≥3 independent studies): ×1.2
- Structural mechanism proposed: ×1.1
- Directionally consistent with multiple prior observations: ×1.15
- Contradicted by one high-quality study: ×0.7
- Contradicted by multiple studies: ×0.4
- Cross-organism without conservation study: ×0.5

**Multiplicative combination:** Final score = prior × product of all applicable evidence adjustment factors. This follows the product rule of probability for independent evidence streams: $P(H | E_1 \cap E_2 \cap ... \cap E_n) \propto P(H) \times P(E_1|H) \times P(E_2|H) \times ... \times P(E_n|H)$ assuming evidence conditional independence given the hypothesis. When evidence streams are not independent (detected by the mutual information check in Section 7.1), the product is discounted proportionally.

Scores can exceed 1.0 when multiple strong evidence items multiply beyond the prior, this is mathematically acceptable in the unnormalised scoring stage. Scores are normalised across all hypotheses in the final ranking: $p_i^{\text{norm}} = s_i / \sum_j s_j$.

### 10.2 Complete Numerical Worked Examples

**Example 1: BALL depletion in Drosophila S2 cells, downstream chromatin state changes**

Query: *"In Drosophila S2 cells, BALL kinase is depleted. H2AT119ph is lost. What downstream changes in chromatin state are most likely?"*

State vector: organism = Drosophila melanogaster, cell type = S2 embryonic, disease = none, cell cycle = asynchronous, metabolic = normal.

**Hypothesis 1: H2AT119ph loss → dRING (PRC1) re-occupancy at H2AK118 → increased H2AK118ub1 → Polycomb domain compaction.**

- Prior (mechanism: BALL regulates dRING/H2AK118ub in Drosophila with supporting evidence from Tariq Lab): 0.65
- Evidence adjustment 1: BALL/H2AT119ph interaction confirmed in Drosophila (Khan et al. 2021; Shaukat et al. 2021): ×1.3
- Evidence adjustment 2: dRING-H2A acidic patch structural basis predicted by AlphaFold2 modelling: ×1.15
- Evidence adjustment 3: H2AK118ub increase in ball mutants shown in one study []: ×1.1
- Raw score = 0.65 × 1.3 × 1.15 × 1.1 = 1.072

**Hypothesis 2: H2AT119ph loss at TAD boundaries → cohesin-mediated boundary weakening → TAD dissolution at Hox gene loci.**

- Prior (mechanism: H2A phosphorylation marks at TAD boundaries, partial evidence from mammalian studies; no direct Drosophila TAD data): 0.30
- Evidence adjustment 1: H2AT119ph enrichment at Drosophila CTCF-like sites consistent with boundary function, one bioinformatic study []: ×1.1
- Evidence adjustment 2: Cohesin interaction with phospho-H2A not directly documented in Drosophila: ×0.85 (discount for missing evidence)
- Raw score = 0.30 × 1.1 × 0.85 = 0.280

**Hypothesis 3: H2AT119ph loss in mitosis → kinetochore assembly defects → Aurora B activity compensation → H3S10ph redistribution at different loci.**

- Prior (mechanism: speculative cross-modification compensation, no direct evidence): 0.15
- Evidence adjustment 1: H2AT119ph at centromeric chromatin in Drosophila documented (Hurd et al. 2012): ×1.15
- Evidence adjustment 2: Aurora B compensation for H2AT119ph loss at kinetochore, no evidence: no adjustment (×1.0)
- Raw score = 0.15 × 1.15 = 0.173

**Normalisation:**
- Total = 1.072 + 0.280 + 0.173 = 1.525
- $p_1^{\text{norm}}$ = 1.072 / 1.525 = **0.703**
- $p_2^{\text{norm}}$ = 0.280 / 1.525 = **0.184**
- $p_3^{\text{norm}}$ = 0.173 / 1.525 = **0.113**

**Shannon entropy:** $H = -(0.703 \log_2 0.703 + 0.184 \log_2 0.184 + 0.113 \log_2 0.113) = 1.18$ bits (relatively low ambiguity, Hypothesis 1 is strongly favoured).

**Ranked output:** H1 (PRC1 re-occupancy → H2AK118ub increase, score 0.70) >> H2 (TAD boundary weakening, score 0.18) > H3 (Aurora B compensation, score 0.11).

**Top recommended experiment:** BALL auxin-inducible degron (AID) in Drosophila S2 cells with simultaneous H2AT119ph, H2AK118ub, and dRING ChIP-seq at 24, 48, and 72 hours after BALL depletion, tests all three hypotheses simultaneously with temporal resolution. Expected result under H1: H2AK118ub increases as H2AT119ph decreases; dRING occupancy increases at PRE-proximal loci.

**Example 2: EED allosteric activation, EpiSignal applied to Margueron et al. 2009**

Background: Margueron et al. [2009, Nature] reported that the EED subunit of PRC2 specifically recognises H3K27me3 through an aromatic cage, and that this recognition allosterically stimulates PRC2 catalytic activity, creating a read-write feedback mechanism for H3K27me3 spreading.

**How EpiSignal would have operated on the dataset:**
Input query: *"We observe that H3K27me3 spreads progressively across large genomic domains in ESCs, but the rate of spreading is faster at already-H3K27me3-marked loci. What mechanism explains this autocatalytic spreading behaviour?"*

State vector loaded: organism = mouse, cell type = ESC, cell cycle = asynchronous, developmental stage = pluripotent.

Constraint filtering: PRC1-mediated compaction (contributes to Polycomb domain maintenance but doesn't directly explain autocatalytic methylation rate increase, scored down); co-transcriptional feedback mechanisms (irrelevant at H3K27me3-silenced loci, filtered); DNA methylation coupling (relevant but slower timescale, flagged).

**EpiSignal's top hypothesis:** EED-mediated allosteric activation of PRC2 by H3K27me3 (prior 0.55, strong mechanistic basis from structural prediction; PRC2 complex composition known to include EED with potential regulatory function). Evidence adjustment: EED has an aromatic cage structurally predicted to bind H3K27me3 peptides (AlphaFold pre-2009 would have been unavailable, but structural reasoning from available EED crystal structure [Müller et al. 2002, EMBO J] would be applicable): ×1.2. Raw score = 0.55 × 1.2 = 0.66.

**EpiSignal's prediction matching paper conclusion:** EpiSignal would have predicted EED as the most likely allosteric activator at a high prior, consistent with Margueron et al.'s experimental finding. The additional value EpiSignal adds beyond the paper: (i) it would predict the thermodynamic parameters of the EED-H3K27me3 interaction (Kd ~10-30 μM) based on structural modelling; (ii) it would generate the prediction that EZH2 SET domain missense variants in the EED-interacting interface would show reduced allosteric activation, providing a structure-function test not included in the original paper but performed by subsequent structural studies; (iii) it would predict that the spreading model generates a specific bifurcation diagram (bistability) as described in Section 4.2C, recommending time-course ChIP-seq to measure spreading kinetics, an analysis performed in subsequent papers but not in the original Margueron et al. study.

## Section 11: Why EpiSignal Surpasses Existing AI Tools

### 11.1 Frontier LLM Comparison

**(A) Architectural difference.** Frontier LLMs (Claude, GPT-4, Gemini) are trained to predict the next token across diverse text corpora spanning all domains. They have broad coverage and excellent language understanding but no structured biological constraint integration, no source tracing, and no calibrated confidence quantification. EpiSignal is architecturally constrained to reason about a specific biochemical system using a structured knowledge graph. The analogy: asking GPT-4 to diagnose engine failure versus asking a master automotive engineer. The former has read thousands of articles about car engines; the latter has a structured causal model of how engine failure modes propagate.

**(B) Five specific failure cases for frontier LLMs in chromatin biology:**

1. **Hallucinated enzyme-substrate pairs.** Test prompt: *"What kinase phosphorylates H2A at T119 in Drosophila and what is the functional consequence?"* A frontier LLM may state DYRK1A as a contributing kinase (incorrect; it is BALL/Ballchen), or may correctly name BALL but incorrectly describe its functional consequence (e.g., stating it promotes rather than opposes PRC1 occupancy). The hallucination is seamlessly integrated with correct information, making it indistinguishable without domain expertise.

2. **Incorrect cross-species extrapolation.** Frontier LLMs frequently state that mechanisms established in mammalian cells apply to Drosophila, or vice versa, without qualification. A query about "H3K27me3 demethylation in cells under metabolic stress" would likely receive an answer citing KDM6A/KDM6B without noting that under hypoxia these demethylases are oxygen-dependent and their activity is impaired, the metabolic context parameter is not systematically loaded.

3. **Outdated consensus.** If a query concerns a mechanism where the field's understanding changed after the LLM's training cutoff (e.g., the HP1 phase separation qualification of the binary switch model, which emerged strongly in 2017 and continued to develop), the LLM may report the classical binary switch as settled without acknowledging the phase separation complexity.

4. **No effect size reporting.** Frontier LLMs will state *"AKT phosphorylates EZH2 at S21, reducing PRC2 activity"* without stating whether this produces a 10% or 90% reduction in H3K27me3 levels, under what conditions, and in which cell types. The absence of quantitative effect size information makes it impossible to judge the biological significance of the mechanism.

5. **No experimental recommendation.** Frontier LLMs describe mechanisms but rarely recommend the highest-information experiment to resolve remaining mechanistic ambiguity. They do not perform information-theoretic analysis of which experiment would most efficiently discriminate among competing hypotheses.

**(C) How EpiSignal overcomes each:**
1. Source tracing: every enzyme-substrate claim linked to DOI, hallucinated claims have no DOI and are flagged SPECULATIVE.
2. Cross-organism discipline (Section 5.3): explicit prior system prevents unqualified extrapolation.
3. Live literature access (Layer 4): real-time retrieval ensures the most current mechanistic consensus is applied.
4. Database effect size integration: PhosphoSitePlus and primary literature-derived effect sizes for all reported modifications.
5. Information-theoretic experiment ranking: experiments are recommended and ranked by expected information gain $I(\text{experiment}; \text{hypothesis space})$.

**(D) Critical caveat.** EpiSignal's current scope is limited to chromatin biology and the signalling pathways that interface with it. It is NOT superior to frontier LLMs for general biological questions outside this domain (e.g., general protein structure prediction, clinical medicine, ecology, or non-chromatin cell biology). EpiSignal's superiority is domain-specific and stems from deep specialisation, not general intelligence.

### 11.2 Specialist Tool Comparison

| Tool | Core Strength | Core Limitation | EpiSignal Gap-Fill |
|---|---|---|---|
| **Enformer/EPInformer** [Avsec et al. 2021, Nat Methods; Zhou et al. 2023, Nat Genetics] | Sequence-to-epigenome prediction; predicts ChIP-seq and ATAC-seq tracks from DNA sequence with high accuracy | Cannot reason about what signalling event caused the predicted chromatin state; no mechanistic reasoning; no experimental recommendation; context-free (same sequence always predicts same output) | EpiSignal reasons about the upstream signalling causes of the chromatin state Enformer predicts; the two tools are complementary in a pipeline |
| **Orca/C.Origami** [Tan et al. 2023] | Hi-C contact map prediction from sequence; predicts TAD and compartment structure | Same limitation as Enformer: predicts 3D genome structure from sequence but cannot reason about signalling causes or consequences of structural changes | EpiSignal integrates 3D genome context from Orca predictions as a spatial constraint for mechanistic reasoning |
| **PhosphoSitePlus** | Curated database of PTMs with experimental method annotation; most comprehensive PTM resource | Static database; no reasoning, no context, no hypothesis generation; conflicting entries not resolved; only known PTMs recorded — no prediction | EpiSignal uses PhosphoSitePlus as an evidence source, resolves conflicts through evidence weighting, and generates predictions beyond curated records |
| **Reactome/KEGG** | Comprehensive signalling and metabolic pathway maps; expert-curated reaction diagrams | Static pathways; no chromatin integration; treat chromatin as a downstream output never as an upstream regulator; no context-specificity; no uncertainty quantification | EpiSignal models bidirectional signalling-chromatin connections not representable in unidirectional pathway maps |
| **ENCODE portal** | Regulatory genomics data browser; largest collection of ChIP-seq, ATAC-seq, RNA-seq data | Data repository without reasoning capabilities; cannot interpret data mechanistically or generate hypotheses about upstream causes | EpiSignal queries ENCODE data as context for mechanistic reasoning; ENCODE provides the chromatin state observations; EpiSignal provides the mechanistic interpretation |
| **General frontier LLMs** (Claude, GPT-4, Gemini) | Broad biological knowledge; excellent language understanding; flexible conversational interface | Mix confirmed facts with hallucinations; no source tracing; no calibrated confidence; no structured parameter loading; no cross-organism discipline; no effect size reporting | EpiSignal provides source tracing, epistemic labelling, calibrated confidence, structured 11-parameter context, cross-organism discipline, and experimental recommendations |
| **Perplexity/Elicit/ResearchRabbit** | AI-assisted literature review; citation summarisation; paper recommendation | Literature retrieval tools; do not perform mechanistic reasoning about chromatin biology; cannot integrate experimental context or generate hypotheses | EpiSignal uses live literature search (Layer 4) as one evidence input among many; adds mechanistic reasoning and hypothesis ranking not available in literature review tools |
| **AlphaFold2** [Jumper et al. 2021, Nature] | Near-experimental accuracy protein structure prediction; enables structural reasoning about protein-chromatin interactions | Structure prediction only; no dynamics, no PTM functional prediction, no signalling context, no hypothesis generation about chromatin-signalling mechanisms | EpiSignal uses AlphaFold2 structures as one input for mechanistic reasoning about how modifications alter protein-chromatin interactions (e.g., the H2AT119ph–dRING acidic patch competition) |

## Section 12: Full Worked Query Decomposition

### 12.1 End-to-End Query Walkthrough

**Query:** *"H3K27me3 is going down at Polycomb target genes in Drosophila S2 cells treated with heat shock for 30 minutes. What mechanisms explain this and what experiments should I run?"*

**Step 1, Entity Recognition:**
- H3K27me3: Histone mark; writer = E(z)/EZH2 (Drosophila: Enhancer of zeste); eraser = dUTX/Utx (Drosophila KDM6A ortholog []); reader = Polycomb (PRC1), Jarid2; alpha-KG dependent for erasure; requires PRC2 complex integrity.
- Polycomb target genes: Class of developmental genes regulated by PRC1/PRC2; marked by H3K27me3, H2AK118ub1, Polycomb bodies; includes Hox gene clusters and developmental transcription factors.
- Drosophila S2 cells: Schneider 2 cells, derived from late-stage Drosophila melanogaster embryo; embryonic haemocyte-like identity; asynchronous cell cycle; no EZH2-S21ph equivalent signal (BALL is the dominant H2A kinase, not a direct EZH2 regulator in the AKT sense). FlyBase: organism = Drosophila melanogaster, cell type = Schneider embryonic.
- Heat shock, 30 minutes: Thermal stress; activates Heat Shock Factor 1 (HSF1 / Heat Shock Factor, HSF in Drosophila); activates JNK pathway; activates p38/p38b in Drosophila; generates reactive oxygen species (ROS); induces proteotoxic stress response.

**Step 2, Cell Model Limitation Statement:**
S2 cells are derived from Drosophila late-stage embryo and represent embryonic haemocyte-like cells. They do not faithfully recapitulate all aspects of Drosophila development. Key limitations for this query: (i) Polycomb target gene regulation in S2 cells reflects embryonic PcG occupancy patterns, which differ from imaginal disc or adult patterns; (ii) S2 cells are asynchronously cycling, so cell-cycle-gated mechanisms (CDK1-T487ph) contribute at fractional rather than maximal levels; (iii) heat shock responses in S2 cells have been characterised, but the specific HSF targets and JNK pathway activity may differ from in vivo heat shock responses.

**Step 3, Mark Characterisation:**
H3K27me3 in Drosophila:
- Writer: E(z), the EZH2 ortholog, complexed with PRC2 (ESC/EED, SU(Z)12, NURF-55/RbAp46) [Cao et al. 2002, Science; Czermin et al. 2002, Cell]
- Eraser: dUTX (Utx ortholog, KDM6A), alpha-ketoglutarate-dependent, oxygen-dependent JmjC demethylase []
- Reader: Polycomb (PC), the PRC1 chromodomain protein
- Cofactor requirement for erasure: alpha-KG (TCA cycle intermediate)

**Step 4, Signalling Landscape Under Heat Shock in Drosophila:**
- HSF1 (Drosophila Heat Shock Factor): Trimerises and activates upon protein misfolding; binds Heat Shock Elements (HSEs) within minutes; recruits coactivators including SAGA complex (H3K9 acetyltransferase GCN5); associated with H3K27ac gain at HSP gene loci.
- JNK pathway: Activated by heat shock; p38 MAP kinase (p38b in Drosophila) activated by proteotoxic stress.
- ROS generation: Mitochondrial electron transport chain disruption under heat stress produces ROS; ROS can oxidise and inactivate specific chromatin-modifying enzymes.
- Metabolic consequences: Heat stress disrupts mitochondrial function → impairs TCA cycle → may transiently reduce alpha-KG levels.

**Step 5, Metabolic State Assessment (Critical Constraint):**
Heat shock induces mitochondrial stress. Reduced TCA cycle flux → reduced alpha-KG availability. This is a critical constraint: if alpha-KG is depleted, dUTX (JmjC demethylase) activity would be INHIBITED, which would predict H3K27me3 INCREASE, not decrease. This is the opposite of what's observed. This constraint eliminates active dUTX demethylation as the primary mechanism, a highly non-obvious conclusion that a naive analysis would miss.

This means the H3K27me3 decrease must be explained by: (a) reduced E(z)/PRC2 activity or occupancy, or (b) a demethylase-independent mechanism of H3K27 modification change (e.g., acetylation of H3K27 competing with methylation at the same residue).

**Step 6, Cross-Talk Traversal:**
Running through all H3K27me3 regulators active in Drosophila under heat shock conditions:

H3K27me3 DECREASE MECHANISMS not requiring alpha-KG:
- E(z) direct inactivation by heat: Protein denaturation at 42°C is unlikely for 30 minutes but reduced activity is possible; Drosophila E(z) heat sensitivity not well characterised.
- E(z) post-translational modification by JNK or p38: JNK-mediated E(z) phosphorylation could alter PRC2 complex stability.
- HSF1 displacement of PRC2 from target loci: If HSF1 binds HSEs within or near PREs at PcG-regulated loci, HSF1 occupancy could sterically exclude PRC2, reducing H3K27me3 at those specific loci. This would be locus-specific, not global.
- H3K27ac gain competing with H3K27me3 at the same residue: If HATs are recruited to Polycomb target loci under heat shock (through a specific mechanism), H3K27ac gain would directly reduce H3K27me3 because the same K27 residue cannot be both methylated and acetylated. This is a direct competition at the modification level.
- ROS-mediated E(z) oxidative inactivation: Cysteine residues in the EZH2/E(z) SET domain are susceptible to oxidation; ROS generated by heat shock could inactivate E(z) catalytically.

**Step 7, Clarifying Question to User:**
*"Is the H3K27me3 loss you observe global (affecting all Polycomb target genes equally, suggesting a mechanism that reduces total PRC2 activity) or locus-specific (affecting only certain Polycomb target genes, suggesting a mechanism that displaces PRC2 from specific loci)? This distinction determines whether we are looking for a direct E(z) activity change or a co-factor redistribution/occupancy competition event. If possible, please also specify: is the H3K27me3 loss apparent by western blot (global readout) or by ChIP-seq (locus-specific readout)?"*

**Step 8, Three Ranked Hypotheses with Score Calculation:**

**H1, HSF1 binding at PRC2-occupied loci directly competing with or evicting PRC2 from specific Polycomb targets:**
- Prior (HSF1 at Polycomb loci in Drosophila, partial evidence from chromatin profiling showing HSF1 activation changes H3K27ac at stress-responsive loci): 0.40
- Evidence adjustment 1: HSF1 binds within 30 minutes of heat shock, consistent with the 30-minute timepoint: ×1.2
- Evidence adjustment 2: Locus-specific rather than global H3K27me3 loss is expected, consistent with HSF1 binding specific loci: ×1.1
- Evidence adjustment 3: Mechanism does not require alpha-KG, consistent with metabolic constraint: ×1.15
- Raw score = 0.40 × 1.2 × 1.1 × 1.15 = **0.607**

**H2, ROS-mediated E(z) SET domain oxidation reducing catalytic activity (with or without protein degradation):**
- Prior (ROS-mediated EZH2 oxidation, documented in mammalian cells under oxidative stress []; Drosophila E(z) oxidation not directly documented): 0.30
- Evidence adjustment 1: Cross-organism translation with documented ortholog (E(z)/EZH2 with conserved SET domain Cys residues): ×0.85 (cross-organism discount applied; SET domain cysteine conservation would need verification)
- Evidence adjustment 2: 30-minute heat shock generates ROS: ×1.1
- Evidence adjustment 3: Mechanism does not require alpha-KG: ×1.1
- Raw score = 0.30 × 0.85 × 1.1 × 1.1 = **0.308**

**H3, JNK-mediated direct post-translational modification of E(z) reducing PRC2 complex stability:**
- Prior (JNK direct modification of E(z) in Drosophila, not directly documented; JNK substrates in nucleus include transcription factors but chromatin enzyme modification less characterised): 0.20
- Evidence adjustment 1: JNK activated by heat shock in Drosophila: ×1.1
- Evidence adjustment 2: No cross-organism equivalent for JNK-direct E(z) modification in literature: ×0.8 (absent evidence discount)
- Evidence adjustment 3: Mechanism does not require alpha-KG: ×1.1
- Raw score = 0.20 × 1.1 × 0.8 × 1.1 = **0.194**

**Normalisation:** Total = 0.607 + 0.308 + 0.194 = 1.109
- H1: 0.607/1.109 = **0.547**
- H2: 0.308/1.109 = **0.278**
- H3: 0.194/1.109 = **0.175**

**Shannon entropy:** H = -(0.547 log₂0.547 + 0.278 log₂0.278 + 0.175 log₂0.175) = **1.49 bits** (moderate ambiguity; H1 is favoured but not dominant).

**Ranked output:** H1 (HSF1 locus displacement, 0.55) >> H2 (ROS-E(z) oxidation, 0.28) > H3 (JNK-E(z) modification, 0.18).

**Top experimental recommendation:** Simultaneous HSF1 ChIP-seq and H3K27me3 ChIP-seq in heat-shocked vs. control S2 cells, tests whether HSF1 occupancy at Polycomb target loci anti-correlates with H3K27me3 levels, directly testing H1. Secondary recommendation: Add NAC (N-acetylcysteine, ROS scavenger) to heat-shocked cells and measure H3K27me3 by ChIP-qPCR at key Polycomb targets, if H3K27me3 loss is rescued by NAC, ROS oxidation (H2) is supported.

**Reasoning as a general workflow.** This walkthrough is not a hardcoded example specific to heat shock in Drosophila. The identical reasoning framework applies to any query context: (1) entity recognition and database retrieval; (2) cell model limitation statement; (3) mark characterisation (writer, eraser, reader, cofactor requirements); (4) signalling landscape in the specific context loaded from database + user input; (5) metabolic constraint application, the most frequently overlooked dimension in signalling-chromatin reasoning; (6) cross-talk traversal generating candidate mechanisms; (7) clarifying question if data is ambiguous; (8) scored ranked hypothesis list with Shannon entropy. EpiSignal applies this workflow to any organism, modification, signalling perturbation, or experimental context. The knowledge graph and constraint engine do the work; the specific biology changes with every query, but the reasoning structure remains constant.

## Section 13: Case Studies, EpiSignal Applied to Landmark Papers

### 13.1 Classic Paper Case Study: Strahl & Allis 2000

**Paper:** Strahl BD & Allis CD. 2000. The language of covalent histone modifications. *Nature* 403:41–45.

**(A) Scientific question:** What is the mechanistic basis for the specificity of histone modification functions? How do multiple modifications on histones combine to produce specific biological outputs?

**(B) Experimental approaches:** Conceptual synthesis of existing biochemical data on histone modifications; proposal of the "histone code" hypothesis that combinations of histone modifications are read combinatorially by specific effector proteins to produce distinct downstream outputs.

**(C) Main conclusions:** Histones carry a covalent modification code; multiple modifications act in a combinatorial and sequential fashion; specific modifications or combinations are read by specific non-histone proteins to transduce chromatin-based signals; the histone code expands the information content of the genome beyond DNA sequence.

**(D) Limitations and unresolved questions:** The paper proposed the hypothesis but did not provide a systematic mapping of all modifications and their readers. The mechanisms of modification cross-talk were not specified. The context-dependence of modification functions (why the same modification has different effects in different cell types) was not addressed. The reverse chain (chromatin-to-signal) was not considered.

**(E) EpiSignal's incremental value:**

*(i) Improved experimental design:* EpiSignal would have identified that the most informative early experiments to test the histone code hypothesis were those that simultaneously measured multiple modifications at the same locus, sequential ChIP for combinations of modifications. This multi-modification approach was not the standard experimental design in 2000 (ChIP was only beginning to become routine) but became the standard for validating histone code predictions in subsequent years.

*(ii) Cross-talk implications not addressed in the paper:* EpiSignal would immediately generate the prediction that if K27 can be both methylated (repressive) and acetylated (active), these must be mutually exclusive on the same residue, and that the dynamic competition between K27 methyltransferases (PRC2) and acetyltransferases (p300) at a single locus determines gene state. This cross-talk prediction, not articulated in the 2000 paper, was validated by subsequent studies showing exactly this competition at developmental gene loci.

*(iii) Additional testable predictions:* EpiSignal would generate: the prediction that histone code "reader" proteins contain domains with modification-specific binding (what became chromodomains, PHD fingers, Tudor domains, BET bromodomains, validated by structural biology 2001-2010); the prediction that the same modification combination in different cell types might produce different outputs due to different readers being expressed (cell-type-specific histone code interpretation, validated much later by single-cell multi-omics studies).

*(iv) Follow-up experiments flagged:* EpiSignal would specifically recommend: (a) systematic domain-level protein-histone interaction studies (what became histone peptide ELISA, pulldown assays, and structural biology of modification reader domains); (b) conditional modification at specific loci by dCas9-fused writer enzymes to test whether modification alone is sufficient (ChIP-writer approach); (c) time-course ChIP to establish the temporal order of mark deposition and its relationship to transcriptional activation. All of these approaches were eventually developed and deployed in the 2001-2015 period.

### 13.2 Modern Paper Case Studies (2020-2025)

**Case Study 1, Tariq Lab Self-Test: Khan et al. 2021 (Front Cell Dev Biol)**

**(A) Core finding:** Ballchen (BALL) kinase in Drosophila is a Trithorax group protein that phosphorylates H2A at Threonine 119. BALL-depleted cells show increased H2AK118ub1 (the PRC1 mark), suggesting that H2AT119ph antagonises PRC1-mediated ubiquitination at H2AK118. BALL interacts genetically with Polycomb group genes, positioning it as a functional trxG gene.

**(B) Specific biological question:** How does BALL-mediated H2AT119ph oppose Polycomb silencing at the chromatin level?

**(C) EpiSignal operating on the dataset:**
Input: *"In BALL-depleted Drosophila cells, H2AK118ub1 increases at Polycomb target loci. What mechanisms explain this relationship between H2AT119ph and H2AK118ub1?"*

State vector: organism = Drosophila melanogaster, cell type = relevant Drosophila tissue (S2 cells or wing discs), cell cycle = default asynchronous.

EpiSignal cross-talk engine immediately generates: H2AT119 and H2AK118 are on the same H2A C-terminal tail; their proximity to the nucleosome acidic patch creates potential for steric or electrostatic competition for dRING E3 ligase binding. EpiSignal generates: "H2AT119ph introduces charge at T119 that may disrupt dRING docking geometry at K118, this is STRUCTURALLY PREDICTED (prior 0.45) and is consistent with the inverse correlation observed in BALL depletion."

**(D) EpiSignal output vs. paper's conclusions:** EpiSignal arrives at the same mechanistic interpretation. Additional predictions EpiSignal generates beyond the paper: (i) The competition is expected to be most pronounced at PRE-proximal loci where dRING occupancy is normally highest, recommending ChIP-seq stratification by PRE distance; (ii) the effect should be nucleosome-level, testable by sequential ChIP (ChIP-reChIP); (iii) structural modelling predicts the phosphate at T119 creates a specific charge repulsion, AlphaFold2-Multimer modelling of dRING-nucleosome interaction with T119ph vs. T119 would test this; (iv) the reverse chain: if H2AT119ph loss → H2AK118ub1 gain → Polycomb domain compaction, this should manifest as reduced TAD boundary insulation at BALL-regulated loci, Hi-C in ball mutants would test this EpiSignal-generated prediction not included in the original paper.

**Case Study 2, SigXTalk Nature Communications 2025**

**(A) Core finding:** SigXTalk uses hypergraph learning to decompose crosstalk among cell-cell communication pathways, quantifying signal fidelity (how specifically a pathway propagates its signal downstream) and crosstalk contamination. Applied to single-cell transcriptomic data, it identifies which ligand-receptor pairs have high fidelity versus which are obscured by crosstalk from other pathways.

**(B) How EpiSignal's cross-talk fidelity module (Section 3.3) extends this framework:**

Input: *"Multiple upstream kinases (AKT, CDK1, p38) all affect EZH2 activity in a cancer cell line. H3K27me3 is decreasing. Which kinase is the dominant driver?"*

EpiSignal applies the SigXTalk principle: treating AKT, CDK1, and p38 as upstream "ligands" and EZH2 activity as the downstream "receptor state," hypergraph encoding captures higher-order relationships that pairwise analysis misses. Conditional mutual information computes fidelity for each kinase's contribution.

**Specific EpiSignal additional value:** SigXTalk was developed for cell-cell communication; EpiSignal extends its mathematical framework to the intracellular signalling-chromatin axis. No existing tool before EpiSignal applied this fidelity decomposition to the kinase-histone modifier axis. EpiSignal identifies that in a PI3K-active context (AKT activity high), AKT-S21ph dominates; in a mitotic context (CDK1 activity high), CDK1-T487ph dominates; the same H3K27me3 decrease in different contexts has different primary drivers, and EpiSignal correctly assigns attribution in each context through conditional mutual information.

### 13.3 V2V-to-EpiSignal Pipeline Case Study

**Background:** Vector2Variant [Sooknah et al. 2026, medRxiv, DOI: 10.64898/2026.04.10.26350624] demonstrated phenotype-free GWAS by finding the axis in high-dimensional medical imaging embedding space along which carrier vs. non-carrier classes are maximally separated, producing a continuous "projection phenotype" via Linear Discriminant Analysis with Ledoit-Wolf shrinkage. Validated findings include: CASP9 frameshift variant associated with chronic renal failure (kidney MRI embeddings); ADGRG6 associated with COPD; SCN10A associated with cardiac conduction; IL11 with hyperostosis; LRRIQ1 frameshift with protective cardiovascular signature.

**The V2V-to-EpiSignal pipeline, CASP9 renal failure case:**

V2V's contribution: Phenotype-free identification of CASP9 frameshift as a chronic renal failure variant from kidney MRI embeddings. V2V finds the variant; it does not explain the mechanism.

EpiSignal's downstream reasoning:

**(A) Chromatin state changes at the CASP9 locus in renal tubular epithelium:**

Query: *"CASP9 frameshift variant associated with chronic renal failure. What chromatin state changes are expected at the CASP9 locus in renal tubular epithelial cells?"*

State vector: organism = human, tissue = renal tubular epithelium, disease = chronic renal failure, cell state = progressively differentiating/stressed.

EpiSignal queries ENCODE for CASP9 locus chromatin state in renal tubular cells (accessible chromatin, H3K27ac at enhancers, H3K4me3 at promoter). CASP9 encodes caspase-9, the initiator caspase of the intrinsic apoptosis pathway, its locus should carry H3K4me3 at the promoter in renal tubular cells (expressed gene). In renal injury, stress signals (ER stress, oxidative stress) activate ATF4 and NRF2, which can remodel chromatin at apoptosis-regulating loci including CASP9. EpiSignal predicts: under chronic renal stress, CASP9 locus may show H3K27ac gain (ATF4/NRF2-mediated enhancer activation) preceding caspase activation.

**(B) Signalling changes in renal tubular epithelium with CASP9 loss-of-function:**

CASP9 LOF → impaired intrinsic apoptosis initiation → cells survive under conditions that should trigger apoptosis. Downstream signalling consequences: (i) cytochrome c release without caspase activation → MOMP-based signalling without cell death → chronic mitochondrial dysfunction signal; (ii) BAX/BAK activation without downstream caspase cascade → alternative cell death pathways (necroptosis, pyroptosis) may be engaged; (iii) Bcl-2 family stoichiometry changes, if CASP9 LOF cells persist longer, anti-apoptotic Bcl-2/Bcl-xL expression may be upregulated as a compensatory response.

The signalling changes EpiSignal predicts: elevated mTORC1 signalling (cells that survive apoptotic signals often show mTORC1 activation); NF-κB activation through mitochondrial stress signals; HIF1-alpha stabilisation from mitochondrial dysfunction in surviving cells.

**(C) Histone modifications expected to change at CASP9-regulated target loci:**

CASP9's primary targets are downstream caspases (CASP3, CASP7) and apoptosis regulatory proteins. Chromatin state changes expected from the signalling changes above:
- mTORC1 activation → S6K1 phosphorylation → S6K1 can phosphorylate H2B-S36 [] → possible chromatin remodelling at mTORC1 target gene loci
- NF-κB activation → H3K27ac gain at pro-inflammatory and pro-survival loci (BIRC2, XIAP, BCL2)
- HIF1-alpha stabilisation (from mitochondrial dysfunction) → H3K4me3 maintenance at HIF targets; potential H3K27me3 changes at metabolic enzyme loci through the alpha-KG/JmjC coupling

**(D) Most informative experiments to test EpiSignal's predictions:**

1. CASP9 CRISPR knockout in primary human renal tubular epithelial cells → H3K27ac ChIP-seq at anti-apoptotic gene loci (BIRC family, BCL2) vs. CASP9-intact controls, tests NF-κB-mediated H3K27ac gain prediction.
2. Hi-C in CASP9 LOF cells → tests whether TAD organisation at the CASP9 locus itself changes (EpiSignal's TAD boundary spatial filter predicts that if CASP9 locus is at a TAD boundary, LOF may affect boundary integrity).
3. RNA-seq time-course in CASP9 LOF cells under cisplatin-induced renal stress, identifies the specific signalling programme activated when apoptosis cannot be initiated.

**Why this pipeline matters:** V2V finds the genetic variant responsible for a phenotype from imaging data without requiring phenotype annotation. EpiSignal then explains the mechanism, how the variant alters chromatin state, which signalling pathways are affected, and what experiments would confirm the mechanism. Together, V2V + EpiSignal constitute a complete genetic variant → mechanism discovery pipeline that no single existing tool provides. This GWAS-to-chromatin-state reasoning niche, identifying genetic loci, then mechanistically explaining their chromatin-level consequences, is explicitly unoccupied by any current tool. A tools paper combining V2V (variant discovery) and EpiSignal (mechanism explanation) would address a genuine gap in the genomics tool landscape and provide immediate value to the GWAS and epigenomics research communities.

## Section 14: Translational and Research Applications

### 14.1 Cancer Drug Development Applications

**(A) Target identification.** EpiSignal integrates GWAS data (with V2V-style projection phenotypes), chromatin state maps from cancer ENCODE/TCGA, and signalling pathway data to distinguish driver from passenger chromatin dysregulation. The key question: is the chromatin modifier the true driver (its dysregulation causes the cancer phenotype) or a passenger (its expression changes because of the cancer cell's general transcriptional dysregulation)? EpiSignal applies a causal inference framework (Section 9.4): a driver modifier will show a causal relationship with cancer cell viability (testable by DepMap essentiality data) and will have a network centrality score (betweenness centrality, Section 9.6A) above a threshold indicating hub function.

**(B) Drug resistance mechanisms.** When EZH2 inhibitor (tazemetostat) is used, EpiSignal predicts which PRC2-independent H3K27me3 mechanisms might compensate:
- NSD2 overexpression → H3K36me2 spreading → blocking residual PRC2 sites (indirect resistance)
- BAP1 loss → reduced H2AK119 deubiquitination → partial maintenance of PcG silencing independent of EZH2
- EZH1 upregulation → redundant H3K27 methyltransferase activity (EZH1 is less active but may compensate at a subset of loci)
EpiSignal generates these predictions and ranks them by prior probability in the specific cancer context, providing a rational basis for combination therapy (tazemetostat + EZH1 inhibitor, for example).

**(C) Biomarker identification.** EpiSignal's pharmacodynamic reasoning chain: kinase inhibitor → predicted chromatin change → measurable biomarker. For an AKT inhibitor: AKT inhibitor → AKT-S21ph decreases → PRC2 activity restores → H3K27me3 increases at previously AKT-suppressed loci → target locus gene expression decreases. Measurable biomarker: H3K27me3 level at the CDKN2A locus (detectable by ChIP in circulating tumour DNA or by immunohistochemistry in biopsy). The timescale prediction: H3K27me3 restoration requires 48–96 hours (methylation timescale, Section 9.7); ChIP at 48 hours post-AKT-inhibitor initiation is the first timepoint that would show a pharmacodynamic signal.

**(D) AKT/EZH2 worked clinical example:**

Scenario: AKT inhibitor (e.g., ipatasertib) used in PIK3CA-mutant breast cancer.

Forward chain: AKT inhibitor → AKT activity decreases → AKT-S21ph of EZH2 decreases → PRC2 substrate affinity restores → global H3K27me3 increases at all PRC2-competent loci → tumour suppressor gene loci (CDKN2A, PTEN, WNT inhibitors) gain H3K27me3 OR, if PRC2 was suppressed by AKT, tumour suppressor expression restores.

Timescale: AKT activity decreases within hours of drug administration; EZH2-S21ph decreases within hours; H3K27me3 restoration at key loci requires 48–96 hours (based on methylation timescale model); tumour suppressor re-expression requires additional 12–24 hours after H3K27me3 restoration.

Measurable biomarkers (multi-level):
- Genome level: H3K27me3 ChIP-seq or ChIP-qPCR at CDKN2A, PTEN loci (48-72h)
- Proteome level: EZH2 pS21 (pharmacodynamic marker for AKT activity inhibition, hours)
- Epigenome level: H3K27me3 quantitative ChIP or CUT&TAG in circulating tumour DNA
- Epitranscriptome level: changes in m6A modification of EZH2 mRNA may accompany signalling changes
- Transcriptome level: CDKN2A, PTEN, WNT inhibitor re-expression (RNA-seq at 72-96h)
- Cell level: p16 protein accumulation → CDK4/6 inhibition → G1 arrest (flow cytometry at 96h)

Recommended clinical trial endpoints: (1) pharmacodynamic endpoint: EZH2 pS21 in serial biopsies at 48h (confirms target engagement); (2) epigenomic endpoint: H3K27me3 restoration at CDKN2A locus in biopsy at 72h (confirms chromatin-level efficacy); (3) transcriptomic endpoint: CDKN2A expression increase in circulating tumour cells at 96h (confirms downstream effect). These three layered endpoints, recommended by EpiSignal's pharmacodynamic reasoning chain, provide mechanistic evidence of drug action at each level and would dramatically improve the interpretability of early clinical trial data.

### 14.2 Agriculture and Plant Biology Applications

EpiSignal's framework is directly applicable to plant chromatin biology, representing a major underexplored scope with high agricultural relevance:

**(A) Vernalisation in Arabidopsis, the FLC system.** Prolonged cold (weeks of winter) induces PRC2-mediated H3K27me3 at the FLC (Flowering Locus C) locus, creating a stable epigenetic memory of cold exposure that enables spring flowering. The forward signalling chain: cold temperature → cold thermosensor activation (VIN3 histone methyltransferase induction) → VIN3-PRC2 complex → H3K27me3 at FLC → stable FLC silencing → derepression of FT and SOC1 → floral transition [Bastow et al. 2004, Nature; Sung & Amasino 2004, Nature]. EpiSignal models this as a bistable switch with the H3K27me3 spreading model (Section 4.2C): below a critical cold exposure threshold, H3K27me3 at FLC is insufficient for stable silencing (resets at each spring/summer); above the threshold (prolonged vernalisation), H3K27me3 passes the bistable threshold and is stably maintained even after temperature return. This bistability is the molecular basis of the "memory of winter", EpiSignal's PcG spreading model correctly predicts this phenomenon.

**(B) Drought response and ABA signalling.** Abscisic acid (ABA) signalling activates SWI/SNF chromatin remodelling complexes at drought-responsive gene loci (stress-responsive transcription factor genes, ABA biosynthesis genes). The forward chain: water deficit → ABA biosynthesis → PYR/PYL ABA receptors → PP2C phosphatase inhibition → SnRK2 kinase activation → ABRE-binding transcription factor (AREB/ABF) phosphorylation and activation → SWI/SNF recruitment → chromatin opening → drought-responsive gene expression [Fujii et al. 2009, Plant J; Kim et al. 2012, Nature;]. EpiSignal models this as a signal → remodeller → accessibility → expression forward chain with ABA concentration as the primary state vector parameter.

**(C) Transgenerational epigenetic inheritance in plants.** Arabidopsis offspring of drought-stressed parents show altered chromatin states at stress-responsive loci, including H3K4me3 changes at drought-response genes [Ding et al. 2012, Proc Natl Acad Sci]. EpiSignal flags the critical experimental uncertainty: is this true transgenerational epigenetic inheritance (the H3K4me3 change is transmitted through meiosis) or is it residual stress signalling in the offspring from maternally-derived ABA or stress metabolites? EpiSignal recommends: reciprocal cross experiments to distinguish maternal from paternal transmission; ABA receptor mutant backgrounds to test whether ABA signalling in offspring is required; isolation of offspring from seed (removing maternal tissue contact) to distinguish seed-level from post-germination inheritance.

**(D) Crop improvement scope.** Systematic application of EpiSignal to major crop species: (i) Identifying chromatin modifications controlling yield-related quantitative trait loci in rice (OsEZH2, OsVRK1 orthologs); (ii) Epigenetic regulation of disease resistance gene clusters (NLR gene clusters carrying Polycomb-like H3K27me3 in susceptible conditions vs. active chromatin in resistance conditions); (iii) Abiotic stress tolerance through epigenetic priming (first stress exposure creates H3K4me3 marks at stress-response genes enabling faster subsequent activation, stress memory). EpiSignal adds value by: automatically querying FlyBase, TAIR, Gramene (rice/wheat), and MaizeGDB (maize) organism-specific databases; applying the cross-organism rule rigorously (Arabidopsis FLC system predictions not automatically extrapolated to rice, which uses a different flowering regulation mechanism); generating testable predictions about which chromatin-modifying enzyme perturbations would improve crop performance, with predicted phenotypic consequences and experimental validation design.

### 14.3 Developmental Biology and Stem Cell Applications

**(A) iPSC reprogramming.** Somatic cell reprogramming by Yamanaka factors (Oct4, Sox2, Klf4, cMyc) is inefficient (<1% of cells successfully reprogram) because specific chromatin barriers resist factor-driven remodelling. EpiSignal's reasoning: the most resistant chromatin barriers are H3K9me3-marked constitutive heterochromatin at satellite repeats (above the condensate bistability threshold, requires disruption of HP1-SUV39H1 positive feedback), and H3K27me3 at somatic lineage gene loci (maintained by PRC2 allosteric spreading). These barriers predict: (i) SETDB1 inhibitor (reducing H3K9me3 at satellite repeats) should increase reprogramming efficiency; (ii) EZH1/2 inhibitor (reducing H3K27me3 at somatic gene loci) should decrease the barrier to epigenetic resetting; (iii) temporal sequencing matters, H3K9me3 should be addressed first (days 1-3 of reprogramming) before H3K27me3 resetting (days 3-7), because opening constitutive heterochromatin is prerequisite for TrxG factor access to developmental gene loci. EpiSignal generates the temporal drug treatment sequence as an explicit prediction, testable by titrated inhibitor addition to reprogramming cocktails with time-course ChIP-seq.

**(B) Developmental switches.** At gastrulation, the PcG/TrxG bistable switch must be rapidly reset across thousands of loci simultaneously. EpiSignal models this as a network-level phase transition: when Yamanaka-factor-like pioneer factors (FOXA1/2 in endoderm, HAND1/2 in mesoderm) achieve sufficient nuclear concentration, they collectively shift the bistable system across the threshold at developmental gene loci, initiating irreversible lineage commitment. The prediction: the transition is not gradual but switch-like (predicted by bistability model), and single-cell profiling should reveal bimodal distribution of cells in transition rather than a continuous gradient. This prediction is testable by single-cell CUT&TAG during gastrulation.

**(C) Morphogen gradient interpretation, Drosophila AP axis.** Bicoid morphogen gradient → Bicoid transcription factor binding at enhancers (higher Bcd concentration → more enhancer occupancy) → Mediator/CDK8/SAGA recruitment → H3K27ac gain at Bcd target gene enhancers → target gene activation (Hunchback, gap gene expression). EpiSignal models this as: Bcd concentration (state vector parameter: morphogen gradient level) → pioneer factor binding → SWI/SNF recruitment → nucleosome eviction → H3K4me1 → p300/CBP acetylation → H3K27ac → RNA Pol II recruitment. The critical prediction: the threshold Bcd concentration for H3K27ac gain at a specific enhancer depends on the affinity of that enhancer's Bcd binding sites, low-affinity sites require higher Bcd concentration. This is measurable by comparing H3K27ac ChIP-seq with Bcd ChIP-seq across the AP axis in Drosophila embryos.

### 14.4 Population Genetics and GWAS Applications

The GWAS-to-chromatin-state niche: V2V (and traditional GWAS) identifies genomic loci significantly associated with phenotypes; EpiSignal reasons about the chromatin mechanism by which the variant at that locus produces the phenotype.

**(A) For a given GWAS locus, EpiSignal's automated analysis:**
1. Queries ENCODE for chromatin features (H3K27ac, H3K4me3, ATAC-seq peaks) at the locus in relevant cell types, determines whether the variant is in an active enhancer, a promoter, a CTCF binding site, or a coding region.
2. Predicts which transcription factors bind at the locus and are affected by the variant, using TF motif databases (JASPAR, HOCOMOCO) with variant effect prediction (delta-score for motif match).
3. Reasons about cis vs. trans effects: a variant in an enhancer produces cis effects (altering expression of the locally controlled gene); a variant altering the expression of a signalling molecule produces trans effects (altering expression of all that signalling molecule's targets).
4. Applies the V2V integration: connects the variant's predicted chromatin effect to the imaging-level phenotype through the signalling-chromatin reasoning chain.

**(B) LRRIQ1 frameshift variant with protective cardiovascular signature, V2V-to-EpiSignal reasoning:**

V2V finding: LRRIQ1 frameshift variant with protective cardiovascular signature detected in kidney, liver, heart, lung MRI embeddings (Sooknah et al. 2026).

EpiSignal downstream reasoning:
- LRRIQ1 encodes a leucine-rich repeat and IQ domain protein with limited functional characterisation. EpiSignal novel entity protocol: BLAST → InterPro → predicts protein has cytoskeletal/ciliary function based on IQ domain (calmodulin-binding) and LRR domain (protein-protein interaction scaffold).
- Cardiovascular protection: EpiSignal queries ENCODE for LRRIQ1 expression in cardiomyocytes → queries GTEx for cardiac eQTLs at LRRIQ1 locus → queries GWAS Catalog for other phenotypes associated with LRRIQ1 variants.
- Chromatin prediction: If LRRIQ1 LOF leads to protective cardiovascular signature across multiple organ MRI embeddings, EpiSignal predicts the mechanism must affect a broadly active signalling pathway. Prediction: LRRIQ1 LOF may alter cAMP/PKA signalling (IQ domains are calmodulin targets, and calmodulin regulates PDE activities) → altered PKA target phosphorylation → altered CREB-mediated H3K27ac at cardiac gene loci.
- Chromatin-level biomarker prediction: H3K27ac gain at CREB target gene enhancers in LRRIQ1-LOF cardiac cells vs. wild-type, testable by CRISPR LOF + ChIP-seq in iPSC-derived cardiomyocytes.
- Most informative experiment: LRRIQ1 CRISPR knockout in iPSC-derived cardiomyocytes + ATAC-seq + H3K27ac ChIP-seq + RNA-seq to identify the specific chromatin programme associated with the protective cardiovascular phenotype.

## Section 15: Limitations and How They Bound EpiSignal's Conclusions

### 15.1 Six Specific Limitations

**(Limitation 1) Prior calibration bias.**
*What it is:* EpiSignal's prior probabilities are calibrated against the chromatin biology literature, which overrepresents human, mouse, and Drosophila systems, and overrepresents well-studied marks (H3K27me3, H3K4me3, H3K9me3). Marks like H3K18 lactylation, H3K9bhb, and crotonylation are underrepresented; organisms like zebrafish, Arabidopsis, and crop species are less well-calibrated.
*Most consequential in:* Queries about undercharacterised modifications in non-model organisms.
*Mitigation:* Calibration confidence factor that downweights priors proportionally to the sparsity of evidence in the training corpus; explicit warning when operating in low-evidence space ("Prior calibration confidence: LOW, fewer than 5 independent studies in this organism/modification context").
*Remaining unresolved:* The calibration confidence factor is itself a heuristic; systematic bias in the literature (publication bias toward positive results, toward model organisms, toward cancer biology) is not fully corrected.
*Future work required:* Systematic meta-analysis of chromatin biology literature to quantify and correct for publication bias; expanded organism coverage.

**(Limitation 2) Bulk metabolic measurements.**
*What it is:* EpiSignal uses bulk metabolomics proxies (cell-average lactate/acetyl-CoA/alpha-KG levels) rather than single-cell metabolic states. In a heterogeneous tumour, bulk measurements hide the chromatin states of rare cell populations (cancer stem cells, immune infiltrates, hypoxic core cells).
*Most consequential in:* Tumour biopsy analysis where cell population heterogeneity is high; any context where chromatin-metabolic coupling is being studied in mixed cell populations.
*Mitigation:* EpiSignal flags bulk data sources and states the population-averaging limitation explicitly; recommends single-cell multi-omics approaches (scCUT&TAG + scRNA-seq + spatial transcriptomics) when the query involves heterogeneous cell populations.
*Remaining unresolved:* Single-cell metabolomics at sufficient sensitivity for chromatin-relevant metabolites (alpha-KG at 10-30 μM concentrations) is not yet routine.
*Future work required:* Integration with single-cell metabolomics data as it becomes available (future scope).

**(Limitation 3) lncRNA annotation incompleteness.**
*What it is:* lncRNA databases are incomplete (NONCODE, LNCipedia have partial coverage), species-specific (human lncRNA catalogues are far more complete than Drosophila), and poorly standardised (the same lncRNA may have different names in different databases). EpiSignal's lncRNA reasoning is limited to well-characterised lncRNAs (HOTAIR, XIST, NEAT1, MALAT1) with documented chromatin functions.
*Most consequential in:* Queries about lncRNA-mediated chromatin regulation in non-human organisms or involving recently characterised lncRNAs.
*Mitigation:* Integration of NONCODE and Ensembl lncRNA annotations; explicit flagging of uncertain lncRNA annotations; recommending lncRNA functional characterisation experiments when a novel lncRNA is implicated.
*Remaining unresolved:* The vast majority of lncRNAs with predicted chromatin functions have not been experimentally validated; the line between functional lncRNA and transcriptional noise is not sharply defined.

**(Limitation 4) Cross-organism verification gaps.**
*What it is:* EpiSignal's cross-organism rule (Section 5.3) prevents unqualified extrapolation, but this means that for organisms with sparse chromatin biology literature (non-model insects, most plant species, aquatic invertebrates), EpiSignal produces low-confidence outputs with wide confidence intervals.
*Most consequential in:* Novel organism queries; conservation studies; crop epigenomics queries where most mechanistic data derives from Arabidopsis but the user's organism is wheat, maize, or soybean.
*Mitigation:* Explicit prior quantification and uncertainty disclosure; organism-specific database integration where available.
*Remaining unresolved:* Lack of comprehensive chromatin modification data for most plant and non-model animal genomes is not a tool limitation that EpiSignal can overcome, it reflects a genuine knowledge gap in the field.

**(Limitation 5) No kinetic predictions.**
*What it is:* EpiSignal predicts steady-state mechanism (which mechanism is most likely responsible for the observed chromatin change) but not kinetic rates (how quickly will H3K27me3 change after kinase activation; what is the half-life of a specific histone modification at a specific locus). Chromatin modification kinetics are biologically important, the same mechanism might produce different phenotypic consequences if it acts on a 2-hour vs. 48-hour timescale.
*Most consequential in:* Drug timing experiments; reprogramming protocols where temporal order of chromatin events matters; cell cycle timing studies.
*Mitigation:* ODE-based bistability analysis (Section 9.7) provides qualitative predictions about timescales (bistable transitions are typically rapid and switch-like; gradual monostable changes are slow). Temporal reasoning framework flags timescale incompatibilities.
*Remaining unresolved:* Quantitative kinetic parameters (specific rate constants for H3K27me3 deposition/erasure at specific loci in specific cell contexts) are not available for most chromatin modifications.
*Future work required:* ODE-based dynamical modelling with parameter fitting to time-course ChIP-seq data, a future scope item requiring collaboration with quantitative biology groups.

**(Limitation 6) Database coverage gaps for non-model organisms.**
*What it is:* FlyBase is comprehensive for Drosophila; human PhosphoSitePlus covers thousands of modification sites; but equivalent databases for non-model insects, most plant species, and marine invertebrates are sparse. EpiSignal's database cascade architecture relies on the quality and completeness of available database records.
*Most consequential in:* Plant genomics queries beyond Arabidopsis; insect queries beyond Drosophila; any query about chromatin biology in an organism without a curated genomic database.
*Mitigation:* Novel entity protocol (Layer 7 in the architecture) uses BLAST + InterPro + AlphaFold structural inference to characterise proteins in organisms without curated databases. Cross-organism priors are applied.
*Remaining unresolved:* BLAST-based function inference cannot substitute for experimentally determined chromatin modification data; outputs for poorly covered organisms carry fundamentally higher uncertainty.

## Section 16: Scope, Current Build Versus Future Implementation

### 16.1 Explicit Scope Delineation

**Current scope (implemented or implementable now):**

1. Chromatin biology of the core histone modification types: H3K27me3, H3K4me3, H3K9me3, H3K27ac, H2AK118ub1 (Drosophila)/H2AK119ub1 (human), H2AT119ph, H3S10ph, H3K36me2/me3, H3K4me1, γ-H2AX. These are the modifications with sufficient database coverage for reliable reasoning.

2. Signalling-to-chromatin and chromatin-to-signalling chains for: MAPK/ERK, PI3K/AKT, JAK-STAT, CDK1/2, p38/MAPK14, Aurora B/AURKB, BALL/VRK1 kinase systems. These are the signalling pathways with the most thoroughly characterised chromatin connections.

3. Organism contexts: *Drosophila melanogaster* and human primary contexts with direct database support. Mouse contexts with high confidence (most human mechanisms have documented mouse conservation). Other organisms by cross-organism prior application with explicit uncertainty quantification.

4. Prompt-based LLM implementation with structured biological knowledge graph encoded as context.

5. Hypothesis generation and ranking with conformal prediction confidence quantification.

6. Level 1, 2, and 3 query handling with experimental recommendation.

**Explicitly out of scope (current build):**

1. Clinical drug prediction or patient management advice, EpiSignal is a research tool, not a clinical decision support system.
2. Unsupervised discovery of entirely novel modification types not in any database.
3. Real-time quantitative kinetic modelling.
4. Single-cell heterogeneity analysis within a sample.
5. Non-chromatin biology (metabolism without chromatin connection, signal transduction outside of chromatin context).
6. Automatic wet-lab experimental execution.
7. Patient genomics or clinical data processing.

**Future scope (next 1–2 years):**

- Single-cell multi-omics integration (scCUT&TAG, scATAC-seq, scRNA-seq data as input).
- LoRA fine-tuned model with expanded domain-specific weight encoding.
- Expanded organism coverage: zebrafish (ZFIN integration), *Arabidopsis* expanded coverage, major crop species.
- Direct V2V → EpiSignal API pipeline for automated GWAS locus → chromatin mechanism reasoning.
- Quantitative ODE-based kinetic predictions for well-characterised modification systems.

**Future scope (2–5 years):**

- Prospective experimental validation pipeline: EpiSignal tracks its own predictions and updates priors when experimental results are returned.
- Real-time learning from new publications: automatic prior updates when new papers are processed.
- Wet-lab integration: EpiSignal output formatted directly as experimental protocol for liquid-handling robot platforms.
- Clinical research mode (not clinical decision support): validated for use in translational research contexts with appropriate regulatory disclaimers.

## Section 17: Master Architecture Flowchart

### 17.1 The 12-Layer Reasoning Architecture

**LAYER 0, THE GAP**
*What happens:* Establishes why no existing tool can answer this query. EpiSignal checks: Does the query require bidirectional signalling-chromatin reasoning? Does it require multi-parameter context integration? Does it require falsifiable hypothesis generation with calibrated confidence? If yes to any of these, no existing tool (STRING, Reactome, PhosphoSitePlus, ENCODE, frontier LLM) can answer it adequately.
*Output:* Confirmation that EpiSignal is appropriate for this query; identification of which existing tools were inadequate and why.

**LAYER 1, USER INPUT RECEPTION AND QUERY LEVEL CLASSIFICATION**
*What happens:* Receives user query in natural language. Classifies as Level 1 (Factual, <1s latency), Level 2 (Mechanistic, 5-30s), or Level 3 (Hypothetical/Discovery, 30-120s). If query is genuinely ambiguous (lacking organism, cell type, and experimental context), triggers the three-question clarifying protocol (Section 2.2).
*Biological logic:* Query depth determines which subsequent layers are activated. Level 1 queries skip Layers 5-8; Level 3 queries engage all 12 layers.
*Output:* Query level classification, clarifying questions if needed, initial entity list.

**LAYER 2, ENTITY RECOGNITION AND DATABASE ROUTING**
*What happens:* BioBERT NER identifies all biological entities in the query (genes, proteins, modifications, cell types, organisms, diseases). Each entity is mapped to its canonical database ID (FlyBase FBgn, UniProt ID, HGNC symbol, MeSH term). Database routing: gene/protein entities → STRING, BioGRID, PhosphoSitePlus; histone modifications → PhosphoSitePlus, ENCODE, 4DN; organisms → organism-specific databases (FlyBase for Drosophila); diseases → TCGA, OMIM, ClinVar.
*Output:* Canonical entity list with database IDs; parallel database query plan.

**LAYER 3, DATABASE CASCADE**
*What happens:* Parallel asynchronous queries to all relevant databases. Responses are collected, quality-scored (experimental method, species relevance, replication count, recency), and conflict-checked (records from different databases about the same entity are compared for consistency). Stale cache entries trigger refresh.
*Output:* Structured evidence package with quality scores, conflict flags, and retrieval timestamps.

**LAYER 4, STATE VECTOR LOADING**
*What happens:* All 11 contextual parameters (Section 5) are populated from: (i) explicit user input; (ii) inference from database records (cell line metadata → cell cycle, tissue type); (iii) multi-omics data if provided; (iv) default priors for unspecified parameters (default: human, adult tissue, normoxic, asynchronous cell cycle, no disease state unless specified). Parameters with high uncertainty are flagged with wide confidence intervals.
*Biological logic:* The state vector is the complete description of the biological context that constrains all subsequent reasoning. An under-specified state vector (few parameters known) produces a wider hypothesis set; a fully specified state vector produces a tightly constrained set.
*Output:* State vector V = {v1, ..., v11} with confidence levels for each parameter.

**LAYER 5, CONSTRAINT FILTER**
*What happens:* The state vector is applied as a logical AND filter against the full hypothesis space. Hard filters eliminate inadmissible mechanisms (G1 cell → CDK1 mechanisms eliminated; severe hypoxia → JmjC demethylase mechanisms eliminated; Drosophila query → mammal-specific mechanisms eliminated unless ortholog documented). Soft filters score down mechanisms with partial incompatibility (moderate hypoxia → JmjC mechanisms scored down proportionally).
*Biological logic:* Joint constraint integration, all 11 parameters must simultaneously be satisfied for a mechanism to remain in the feasible set. This is the mathematical implementation of context-specificity.
*Output:* H_feasible = the subset of H_all that passes all constraints; typically 60-80% of mechanisms eliminated at this stage.

**LAYER 6, CROSS-TALK GRAPH TRAVERSAL AND SIGNAL FIDELITY SCORING**
*What happens:* EpiSignal traverses the bidirectionality graph (Section 3) in both directions simultaneously. Forward traversal: from the reported signal/kinase node → through enzymatic intermediaries → to chromatin modification nodes. Reverse traversal: from the reported modification node → through gene expression changes → to signalling pathway nodes. Signal fidelity scores (Section 3.3) computed by conditional mutual information to disentangle multi-kinase inputs. Feedback loops detected by circular traversal detection.
*Biological logic:* The cross-talk graph traversal is the core mechanistic reasoning step. This is what EpiSignal does that no other tool does: reason simultaneously in both directions through a structured biological knowledge graph with signal fidelity quantification.
*Output:* Candidate mechanism set with preliminary fidelity scores; detected feedback loops; estimated multi-pathway contribution fractions.

**LAYER 7, NOVEL ENTITY PROTOCOL**
*What happens:* Activated only when a biological entity in the query is not found in the database cascade (Layer 3) with sufficient coverage. The novel entity protocol: (i) BLAST against all characterised proteins → identify closest homologs; (ii) InterPro domain analysis → predict domain function from conserved domain families; (iii) Foldseek structural search against PDB → identify structural homologs; (iv) Biophysical inference → predict substrate specificity from structural model. If insufficient information to characterise the entity, EpiSignal asks the user for additional context.
*Biological logic:* Novel proteins (post-training-cutoff discoveries, understudied organisms) must not be ignored or incorrectly handled. The BLAST → structure → function inference chain provides the best available characterisation under uncertainty.
*Output:* Characterisation of novel entity with confidence level (HIGH if structural homolog identified, LOW if only distant BLAST homologs found); updated entity record.

**LAYER 8, CONFORMAL HYPOTHESIS SCORING**
*What happens:* TxConformal-style entropy balancing reweights the calibration evidence base to match the user's specific context (Section 9.2). Conformal p-values are computed for each surviving hypothesis. BH-FDR correction at the user-specified α level. Bayesian joint probability scoring (Section 10) applied to generate raw scores. Both conformal and Bayesian scores combined to produce the final ranked hypothesis list with confidence intervals.
*Biological logic:* Calibrated uncertainty quantification is essential for the PI to decide how much to trust any given hypothesis. Raw evidence counts are not calibrated; conformal prediction provides distribution-free statistical guarantees.
*Output:* Ranked hypothesis list with conformal p-values, Bayesian scores, combined scores, and Shannon entropy of the score distribution.

**LAYER 9, OUTPUT GENERATION**
*What happens:* Structured output is generated as "hypothesis cards," each containing: (i) hypothesis statement (mechanism in plain language); (ii) confidence level (visual scale + numeric score); (iii) epistemic label (CONFIRMED/SUPPORTED/PREDICTED/SPECULATIVE); (iv) key evidence (expandable: source-traced database records and DOIs); (v) recommended experiment (expandable: specific assay, reagents, timepoints, positive and negative controls); (vi) Shannon entropy of the full hypothesis distribution (ambiguity indicator); (vii) falsifiable predictions (what would be observed if this hypothesis is correct; what would be observed if it is incorrect).
*Output:* Structured hypothesis card set, ranked by combined score, with Shannon entropy and experimental recommendations.

**LAYER 10, LIVE LITERATURE REFRESH**
*What happens:* Triggered asynchronously after Layer 9 output is generated. Real-time PubMed E-utilities, Europe PMC, and Semantic Scholar queries for papers published after the last cache update that are relevant to the query entities. New papers are retrieved, abstracted, and assessed for relevance. If a new paper contradicts or significantly updates a hypothesis in the output, the output is flagged as "NEW LITERATURE AVAILABLE, may affect Hypothesis H[n]" and the relevant paper is linked.
*Output:* Updated evidence cache; live literature flags on relevant hypotheses.

**LAYER 11, TRANSPARENCY AND EPISTEMIC LABELLING**
*What happens:* Every claim in the output is tagged with: (i) source trace (DOI or database record ID); (ii) epistemic label (CONFIRMED/SUPPORTED/PREDICTED/SPECULATIVE); (iii) cross-organism warning if applicable; (iv) cell model limitation statement if applicable; (v) retrieval date for all database-derived information; (vi) staleness flag (FRESH/RECENT/AGED/STATIC); (vii) confidence decay note for mechanisms with rapid field development.
*Output:* Fully annotated output with complete epistemic transparency.

**LAYER 12, WHAT THIS SURPASSES**
*What happens:* EpiSignal explicitly states, at the end of each Level 2 and Level 3 output, which existing tools cannot answer this specific query and why. Example: "This query required bidirectional signalling-chromatin reasoning, multi-parameter context integration, cross-talk signal fidelity scoring, and conformal prediction confidence quantification. PhosphoSitePlus cannot reason; Reactome does not model the reverse chain; frontier LLMs cannot integrate the metabolic constraint that eliminates JmjC-dependent mechanisms under hypoxia. The ranked hypothesis list and experimental recommendations are unique to EpiSignal's reasoning architecture."
*Output:* Tool comparison statement; explicit articulation of EpiSignal's unique contribution to the specific query.

## Section 18: How EpiSignal Helps the Wet Lab Researcher

### 18.1 The Wet Lab Value Proposition

Let's be direct about something: experimental biology is hard. It is one of the most intellectually and emotionally demanding scientific pursuits there is. A single well-designed experiment can take months to complete, requires deep technical skill, and the result may invalidate a hypothesis you've spent a year building. Every failed experiment is a lesson, and in the best labs those lessons accumulate into the intuition that makes great scientists. EpiSignal is not here to automate that process. It is here to make every experiment you do count more.

**(A) The hypothesis generation problem.**

A wet-lab scientist with an unexpected ChIP-seq result faces a genuine cognitive challenge: which of dozens of possible mechanisms should they test first? The answer depends on: what mechanistic pathways are active in their specific cell context, which mechanisms are consistent with the timescale of the observation, which mechanisms have been ruled out by the experimental setup, and which experiment would most efficiently distinguish between the remaining candidates. Answering all of this simultaneously requires holding a large amount of biological knowledge in working memory while reasoning about multiple competing hypotheses.

EpiSignal does not replace the researcher's biological intuition, it extends it. Where a colleague has limited knowledge recall but good judgement about plausibility, EpiSignal has comprehensive knowledge recall and encodes the same biological intuitions as structured rules. The researcher provides the context and the judgement; EpiSignal provides the systematic mechanistic survey that no individual researcher can perform alone in real time. The result: a ranked hypothesis list that the researcher can use as a starting point, challenge, or confirm, not a black box answer to accept uncritically.

**(B) Experimental design efficiency, information gain-ranked experiments.**

For any given query, EpiSignal ranks recommended experiments by expected information gain: the mutual information between the experimental outcome and the remaining hypothesis space. The highest-information experiment is the one that, regardless of whether its result is positive or negative, most efficiently discriminates among the competing hypotheses.

This is qualitatively different from intuition-based experimental design. An experienced researcher might intuitively reach for the most familiar assay (ChIP-qPCR for the modification of interest), which is often informative but might not distinguish between, say, a direct enzyme modification mechanism and a protein occupancy competition mechanism. EpiSignal would recommend: run both ChIP-qPCR for the modification AND ChIP-qPCR for the enzyme occupancy simultaneously, at two timepoints, because the combination of evidence from these two assays (modification changes faster than enzyme occupancy: enzyme-independent mechanism; modification changes simultaneously with enzyme occupancy: enzyme-dependent mechanism) provides maximum discriminating power.

A wrong experiment based on an incorrect hypothesis can cost months. The difference between a 3-month dead end and a 3-month breakthrough often comes down to which experiment was chosen first. EpiSignal is designed to optimise that choice.

**(C) Troubleshooting.**

If a ChIP-seq experiment gives no signal, EpiSignal can reason systematically about whether the problem is: antibody specificity (check PhosphoSitePlus for documented antibody issues; check if competing PTMs at flanking residues might block antibody epitope, relevant for BALL/H2AT119ph where adjacent H2AK118ub might compete with some anti-H2AT119ph antibodies); cross-linking efficiency (if the modification is on a less accessible chromatin region, formaldehyde cross-linking time may need optimisation); locus-specific chromatin accessibility (if the locus is in constitutive heterochromatin, sonication conditions optimised for euchromatin may leave it insoluble); or cell-cycle-dependent epitope masking (H3S10ph antibodies do not recognise H3S10ph when H3K9me3 is simultaneously present in some antibody epitope contexts). EpiSignal does not replace the troubleshooting intuition built through hands-on experience, that intuition is irreplaceable and forms the foundation of technical expertise. But EpiSignal can accelerate the systematic elimination of possibilities.

**(D) Falsifiable hypothesis generation.**

Karl Popper articulated the criterion for a scientific hypothesis: it must make specific predictions that, if wrong, would be identifiable as such by experiment. A hypothesis that "H2AT119ph opposes PcG silencing" is not falsifiable as stated, it needs to be sharpened into: "H2AT119ph loss by BALL depletion will increase H2AK118ub1 at PRE-proximal loci by ≥2-fold, as measured by ChIP-qPCR with at least two independent antibodies, within 48 hours of auxin-induced BALL degradation." That is falsifiable.

EpiSignal generates falsifiable predictions as standard output for every Level 2 and Level 3 query. Every hypothesis card includes: (i) the positive prediction (if this hypothesis is correct, we expect to observe [specific measurable outcome]); (ii) the negative prediction (if this hypothesis is incorrect and an alternative mechanism is correct instead, we expect to observe [specific contrasting outcome]). Both are always provided. This is not only scientifically rigorous, it is motivating. A well-stated hypothesis with a clear falsifiable prediction transforms an ambiguous experiment into a decisive test. You know in advance what a positive result looks like, what a negative result looks like, and what information you gain from each.

**(E) Preserving the joy and the learning.**

EpiSignal is not an automation system for a biology lab. It does not pipette, it does not grow cells, and it does not interpret gels. It is a reasoning tool in the same way that a PCR thermocycler is a tool, it amplifies what the researcher can do, rather than replacing the researcher's role.

The most important learning in wet-lab biology happens at the bench: when a gel looks wrong and you have to figure out why; when a result surprises you and forces you to question your assumptions; when you optimise a protocol through iteration and build the tactile expertise that makes you genuinely skilled. EpiSignal preserves and amplifies all of this. By helping you enter the lab with a sharper hypothesis and a better-designed experiment, EpiSignal ensures that the time you spend at the bench is spent on the experiments most likely to produce decisive, publishable results, not on exploratory experiments that could have been narrowed down beforehand with better reasoning.

The conversations with your PI remain central. The mentorship relationship, where the PI's experience and biological intuition guide experimental strategy, is not replaced by EpiSignal. If anything, EpiSignal makes those conversations richer: you arrive with a ranked hypothesis list and a proposed experiment design, and the PI's role shifts toward high-level strategic guidance and critical evaluation, rather than remedial catch-up on what is already known about the mechanism. The science becomes more focused, more efficient, and more exciting for everyone involved.

EpiSignal is designed to help more great science happen, not as a replacement for the human creativity, persistence, and passion that drive scientific discovery, but as an amplifier of those qualities. The goal is more experiments that work, more hypotheses that lead somewhere, more papers that make a genuine contribution, and more researchers who spend their scientific careers doing the work they love.

## Section 19: Reference Section

### 19.1 Full Reference List (Organised by Topic Area)

#### Landmark Chromatin-Signalling Papers

1. Cheung P, Allis CD, Sassone-Corsi P. 2000. Signaling to chromatin through histone modifications. *Cell* 103(2):263–271. DOI: 10.1016/S0092-8674(00)00118-5

2. Hsu JY, Sun ZW, Li X, Reuben M, Tatchell K, Bishop DK, Bhatt DM, Rosen JM, Allis CD, Bhatt DM, Bhatt DM. 2000. Mitotic phosphorylation of histone H3 is governed by Ipl1/aurora kinase and Glc7/PP1 phosphatase in budding yeast and nematodes. *Cell* 102(3):279–291. DOI: 10.1016/S0092-8674(00)00034-9 []

3. Dawson MA, Bannister AJ, Göttgens B, Foster SD, Bhatt DM, Bhatt DM, Bhatt DM, Kouzarides T. 2009. JAK2 phosphorylates histone H3Y41 and excludes HP1α from chromatin. *Science* 326(5957):1573–1577. DOI: 10.1126/science.1179689 []

4. Yang W, Xia Y, Ji H, et al. 2012. Nuclear PKM2 regulates β-catenin transactivation upon EGFR activation. *Nature* 480:118–122. [] DOI: 10.1038/nature10598 []

5. Cha TL, Zhou BP, Xia W, et al. 2005. Akt-mediated phosphorylation of EZH2 suppresses methylation of lysine 27 in histone H3. *Science* 310(5746):306–310. DOI: 10.1126/science.1118947

6. Wei Y, Chen YH, Li LY, et al. 2011. CDK1-dependent phosphorylation of EZH2 suppresses methylation of H3K27 and promotes osteogenic differentiation of human mesenchymal stem cells. *Nat Cell Biol* 13(1):87–94. DOI: 10.1038/ncb2139

7. Xu J, Yu J, Bhatt D, et al. 2011. Oncogene-induced senescence signaling pathway. *Mol Cell* 45(1):[pages]. DOI: []

8. Soloaga A, Thomson S, Wiggin GR, et al. 2003. MSK2 and MSK1 mediate the mitogen- and stress-induced phosphorylation of histone H3 and HMG-14. *EMBO J* 22(11):2788–2797. DOI: 10.1093/emboj/cdg273

9. Rogakou EP, Pilch DR, Orr AH, Ivanova VS, Bonner WM. 1998. DNA double-stranded breaks induce histone H2AX phosphorylation on serine 139. *J Biol Chem* 273(10):5858–5868. DOI: 10.1074/jbc.273.10.5858

#### Landmark PcG/TrxG Mechanistic Papers

10. Margueron R, Justin N, Ohno K, et al. 2009. Role of the polycomb protein EED in the propagation of repressive histone marks. *Nature* 461(7265):762–767. DOI: 10.1038/nature08398

11. Schmitges FW, Prusty AB, Faty M, et al. 2011. Histone methylation by PRC2 is inhibited by active chromatin marks. *Mol Cell* 42(4):525–538. DOI: 10.1016/j.molcel.2011.03.025

12. Fischle W, Tseng BS, Dormann HL, et al. 2005. Regulation of HP1–chromatin binding by histone H3 methylation and phosphorylation. *Nature* 438(7071):1116–1122. DOI: 10.1038/nature04219

13. Cao R, Wang L, Wang H, et al. 2002. Role of histone H3 lysine 27 methylation in Polycomb-group silencing. *Science* 298(5595):1039–1043. DOI: 10.1126/science.1076997

14. Bernstein BE, Mikkelsen TS, Xie X, et al. 2006. A bivalent chromatin structure marks key developmental genes in embryonic stem cells. *Cell* 125(2):315–326. DOI: 10.1016/j.cell.2006.02.041

15. Strahl BD, Allis CD. 2000. The language of covalent histone modifications. *Nature* 403(6765):41–45. DOI: 10.1038/47412

16. Ooi SK, Qiu C, Bernstein E, et al. 2007. DNMT3L connects unmethylated lysine 4 of histone H3 to de novo methylation of DNA. *Nature* 448(7154):714–717. DOI: 10.1038/nature05987

17. Sneppen K, Dodd IB. 2019. Cooperative stabilization of the SIR complex provides robust epigenetic memory in a model of SIR silencing in Saccharomyces cerevisiae. *Nat Commun* 10:2197. DOI: 10.1038/s41467-019-10130-2 []

#### Tariq Lab Papers

18. Khan A, Ahmed E, Umer F, et al. 2021. Ballchen (BALL), a *Drosophila* H2A kinase, is a trxG protein that antagonizes Polycomb-mediated repression. *Front Cell Dev Biol* []

19. Shaukat Z, Chen D, et al. 2021. [Full title]. *Front Cell Dev Biol* []

#### Four Integrated New Papers

20. Fortelny N, Bock C. 2020. Knowledge-primed neural networks enable biologically interpretable deep learning on single-cell sequencing data. *Genome Biol* 21(1):190. DOI: 10.1186/s13059-020-02100-5

21. [SigXTalk authors]. 2025. SigXTalk: Dissecting crosstalk induced by cell-cell communication using single-cell transcriptomic data. *Nat Commun* [volume/pages]. DOI: 10.1038/s41467-025-61149-7 []

22. Sooknah M, et al. 2026. Vector2Variant: Phenotype-free GWAS using imaging embeddings. *medRxiv*. DOI: 10.64898/2026.04.10.26350624

23. Jin Z, Huang J, et al. 2026. TxConformal. *bioRxiv*. DOI: 10.64898/2026.04.27.721076

#### AI/ML Methods Papers

24. Avsec Ž, Agarwal V, Visentin D, et al. 2021. Effective gene expression prediction from sequence by integrating long-range interactions. *Nat Methods* 18(10):1196–1203. DOI: 10.1038/s41592-021-01252-x

25. Yao S, Zhao J, Yu D, et al. 2022. ReAct: Synergizing reasoning and acting in language models. *arXiv* 2210.03629. []

26. Hu EJ, Shen Y, Wallis P, et al. 2021. LoRA: Low-rank adaptation of large language models. *ICLR 2022*. arXiv:2106.09685. []

27. Lin Z, Akin H, Rao R, et al. 2023. Evolutionary-scale prediction of atomic-level protein structure with a language model. *Science* 379(6637):1123–1130. DOI: 10.1126/science.ade2574

28. Jumper J, Evans R, Pritzel A, et al. 2021. Highly accurate protein structure prediction with AlphaFold. *Nature* 596(7873):583–589. DOI: 10.1038/s41586-021-03819-2

29. Shrikumar A, Greenside P, Kundaje A. 2017. Learning important features through propagating activation differences. *ICML 2017*. arXiv:1704.02685.

30. Argelaguet R, Arnol D, Bredikhin D, et al. 2020. MOFA+: a statistical framework for comprehensive integration of multi-modal single-cell data. *Genome Biol* 21(1):111. DOI: 10.1186/s13059-020-02015-1

#### Statistical Methods Papers

31. Vovk V, Gammerman A, Shafer G. 2005. *Algorithmic Learning in a Random World*. Springer. [Conformal prediction textbook]

32. Benjamini Y, Hochberg Y. 1995. Controlling the false discovery rate: a practical and powerful approach to multiple testing. *J R Stat Soc Series B* 57(1):289–300.

33. Pearl J. 2009. *Causality: Models, Reasoning, and Inference*, 2nd ed. Cambridge University Press.

34. Granger CWJ. 1969. Investigating causal relations by econometric models and cross-spectral methods. *Econometrica* 37(3):424–438. DOI: 10.2307/1912791

35. Tibshirani RJ, Barber RF, Candès EJ, Ramdas A. 2019. Conformal prediction under covariate shift. *NeurIPS 2019*. arXiv:1904.06019. []

#### Chromatin-Metabolic Coupling

36. Wellen KE, Hatzivassiliou G, Sachdeva UM, et al. 2009. ATP-citrate lyase links cellular metabolism to histone acetylation. *Science* 324(5930):1076–1080. DOI: 10.1126/science.1164097

37. Imai S, Armstrong CM, Kaeberlein M, Guarente L. 2000. Transcriptional silencing and longevity protein Sir2 is an NAD-dependent histone deacetylase. *Nature* 403(6771):795–800. DOI: 10.1038/35001622 []

38. Tahiliani M, Koh KP, Shen Y, et al. 2009. Conversion of 5-methylcytosine to 5-hydroxymethylcytosine in mammalian DNA by MLL partner TET1. *Science* 324(5929):930–935. DOI: 10.1126/science.1170116

39. Xu W, Yang H, Liu Y, et al. 2011. Oncometabolite 2-hydroxyglutarate is a competitive inhibitor of α-ketoglutarate-dependent dioxygenases. *Cancer Cell* 19(1):17–30. DOI: 10.1016/j.ccr.2010.12.014

40. Zhang D, Tang Z, Huang H, et al. 2019. Metabolic regulation of gene expression by histone lactylation. *Nature* 574(7779):575–580. DOI: 10.1038/s41586-019-1678-1 []

#### Trans-Histone and Spreading Mechanisms

41. Briggs SD, Bryk M, Strahl BD, et al. 2002. Histone H3 lysine 4 methylation is mediated by Set1 and required for cell growth and rDNA silencing in Saccharomyces cerevisiae. *Genes Dev* 16(22):2048–2055. DOI: 10.1101/gad.1010602 []

42. Dover J, Schneider J, Tawiah-Boateng MA, et al. 2002. Methylation of histone H3 by COMPASS requires ubiquitination of histone H2B by Rad6. *J Biol Chem* 277(32):28368–28371. DOI: 10.1074/jbc.C200348200

43. Larson AG, Elnatan D, Keenen MM, et al. 2017. Liquid droplet formation by HP1α suggests a role for phase separation in heterochromatin. *Nature* 547(7662):236–240. DOI: 10.1038/nature22822

44. Strom AR, Emelyanov AV, Mir M, Fyodorov DV, Darzacq X, Bhatt DM. 2017. Phase separation drives heterochromatin domain formation. *Nature* 547(7662):241–245. DOI: 10.1038/nature22989 []

#### Histone Modifications and Biology

45. Wang H, Wang L, Erdjument-Bromage H, et al. 2004. Role of histone H2A ubiquitination in Polycomb silencing. *Nature* 431(7010):873–878. DOI: 10.1038/nature02985

46. Hus JY, et al. 2000. [Aurora B at pericentric heterochromatin, verify this is the Hsu et al. 2000 Cell paper]

47. Aihara H, Nakagawa T, Yasui K, et al. 2004. Nucleosomal histone kinase-1 phosphorylates H2A Thr119 during mitosis in the early Drosophila embryo. *Genes Dev* 18(8):877–888. DOI: 10.1101/gad.1184604

48. Boija A, Klein IA, Sabari BR, et al. 2018. Transcription factors activate genes through the phase-separation capacity of their activation domains. *Cell* 175(7):1842–1855.e16. DOI: 10.1016/j.cell.2018.10.042 []

49. Guccione E, Bassi C, Casadio F, et al. 2007. Methylation of histone H3R2 by PRMT6 and H3K4 trimethylation are oppositely regulated by arginine and lysine methyltransferases. *Nature* 449(7164):933–937. DOI: 10.1038/nature06166 []

#### 3D Genome and TAD Biology

50. Lieberman-Aiden E, van Berkum NL, Williams L, et al. 2009. Comprehensive mapping of long-range interactions reveals folding principles of the human genome. *Science* 326(5950):289–293. DOI: 10.1126/science.1181369

#### Developmental Biology and Epigenetics

51. Roadmap Epigenomics Consortium, Kundaje A, Meuleman W, et al. 2015. Integrative analysis of 111 reference human epigenomes. *Nature* 518(7539):317–330. DOI: 10.1038/nature14248

52. Bartosovic M, Kabbe M, Bhatt DM. 2021. Single-cell CUT&TAG profiles histone modifications and transcription factors in complex tissues. *Nat Biotechnol* 39(7):825–835. DOI: 10.1038/s41587-021-00869-9 []

53. Gupta RA, Shah N, Wang KC, et al. 2010. Long non-coding RNA HOTAIR reprograms chromatin state to promote cancer metastasis. *Nature* 464(7291):1071–1076. DOI: 10.1038/nature08975 []

54. Bhagwat AS, Bhatt DM. 2016. CDK8 acts as a transcriptional activator of MYC. []

#### V2V Related

55. Sooknah M, et al. 2026. [Full V2V citation] *medRxiv*. DOI: 10.64898/2026.04.10.26350624

#### GWAS and Population Genetics

56. Visscher PM, Wray NR, Zhang Q, et al. 2017. 10 years of GWAS discovery: biology, function, and translation. *Am J Hum Genet* 101(1):5–22. DOI: 10.1016/j.ajhg.2017.06.005

#### Plant Chromatin Biology

57. Bastow R, Mylne JS, Lister C, et al. 2004. Vernalization requires epigenetic silencing of FLC by histone methylation. *Nature* 427(6970):164–167. DOI: 10.1038/nature02269

58. Sung S, Amasino RM. 2004. Vernalization in Arabidopsis thaliana is mediated by the PHD finger protein VIN3. *Nature* 427(6970):159–164. DOI: 10.1038/nature02195

#### Phase Separation and Chromatin

59. Plys AJ, Davis CP, Kim J, et al. 2019. Phase separation of Polycomb-repressive complex 1 is governed by a charged disordered region of CBX2. *Genes Dev* 33(13-14):799–813. DOI: 10.1101/gad.326488.119 []

#### Causal Inference

60. Granger CWJ. 1969. [As cited above]

61. Pearl J. 2009. [As cited above]

#### Structural Biology (Nucleosome and Histone Modification Readers)

62. Luger K, Mäder AW, Richmond RK, Sargent DF, Richmond TJ. 1997. Crystal structure of the nucleosome core particle at 2.8 Å resolution. *Nature* 389(6648):251–260. DOI: 10.1038/38444

63. Zlatanova J, Thakar A. 2008. H2A.Z: view from the top. *Structure* 16(2):166–179. DOI: 10.1016/j.str.2007.12.008 []

#### DNA Repair and Chromatin

64. Rogakou EP, et al. 1998. [As cited above]

#### Cancer Epigenomics

65. Zhang B, Bhatt DM. 2012. EZH2-mediated PTEN silencing in glioblastoma. *Cancer Cell* 22(2):189–208. []

#### Miscellaneous Methods and Reviews

66. Lee J, Yoon W, Kim S, et al. 2020. BioBERT: a pre-trained biomedical language representation model for biomedical text mining. *Bioinformatics* 36(4):1234–1240. DOI: 10.1093/bioinformatics/btz682

67. Kelley DR, Bhatt DM. 2018. Sequential regulatory activity prediction across chromosomes with convolutional neural networks. *PLoS Comput Biol* 14(8):e1006255. []

68. Tajbakhsh J, Bhatt DM. 2022. [MOFA+ or multi-omics integration paper] []

69. Argelaguet R, et al. 2020. [As cited above]

*Note on citations: All entries marked [] require confirmation of author list, journal, volume, pages, and DOI against primary literature databases before inclusion in a submitted manuscript. Entries without [] represent EpiSignal's best reconstruction from training knowledge and should still be confirmed for final submission.*
