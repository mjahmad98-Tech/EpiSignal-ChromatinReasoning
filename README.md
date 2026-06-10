# EpiSignal — Context-Aware Mechanistic Reasoning Agent for Chromatin Biology

**Status: Architecture and framework in active development**
**Author: Mujtaba Ahmed | Tariq Lab, LUMS**

---

## What this is

EpiSignal is a domain-specific reasoning system I am building to address a gap I kept running into directly in my own chromatin biology research: when a ChIP-seq experiment returns a surprising result, there is no tool that reasons mechanistically about what caused it given your specific experimental context — organism, cell type, metabolic state, disease background, and cell cycle stage all at once.

Frontier AI models like GPT-4 and Claude will answer chromatin biology questions, but they hallucinate mechanisms confidently, apply cross-organism analogies without conservation evidence, and cannot distinguish confirmed facts from plausible inventions. Specialist databases like STRING, PhosphoSitePlus, and Reactome are comprehensive but they do not reason — they are lookup tools, not inference systems. The researcher is left alone with an anomalous result and no structured way to move from observation to ranked, testable mechanistic hypothesis.

EpiSignal is designed to fill that gap.

---

## The core problem it solves

Standard tools treat chromatin as a downstream output of signalling. EpiSignal reasons in both directions:

- **Forward chain** (signal → chromatin): how do kinase activation, metabolic shifts, and remodeller deployment drive histone modification changes
- **Reverse chain** (chromatin → signal): how do chromatin state changes at specific loci feed back to regulate signalling pathway activity, gene expression of pathway components, and cell fate decisions

No existing tool models this bidirectionality systematically. The reverse chain — where chromatin state is an upstream regulator of signalling — is almost entirely absent from current computational tools, yet it is mechanistically real and biologically critical. PTEN silencing by H3K27me3 constitutively activating PI3K/AKT is one example. BALL-mediated H2AT119ph opposing PRC1 occupancy in Drosophila, with downstream consequences for TAD boundary insulation, is another and forms the direct connection to my experimental work in the Tariq Lab.

---

## Current stage

This repository contains the architectural framework and design documentation. I am at the conceptual and systems design stage — the intellectual work of defining what the system needs to do, why existing approaches fall short, and how the reasoning architecture should be structured.

The design has gone through several rounds of critical revision, including:

- Identifying that 11 parameters are insufficient and the parameter system should encode probability distributions, not categorical labels
- Recognising that cross-parameter interactions (hypoxia compounding with IDH mutation on JmjC activity; M-phase overriding transcription regardless of other active pathways) must be explicitly encoded, not inferred
- Proposing a Cellular State Consequence Map architecture to capture chromatin-relevant consequences of complete cell biology without requiring whole-cell simulation
- Designing an Epistemic Completeness Checker that audits every query before reasoning begins and turns knowledge gaps into explicit experimental recommendations
- Scoping deliberately to human and Drosophila only to ensure depth over false breadth

Implementation is the planned next phase.

---

## Repository structure

```
EpiSignal-ChromatinReasoning/
│
├── README.md                          ← this file
│
├── architecture/
│   ├── EpiSignal_Architecture_Document_v1.md   ← 19-section full architecture
│   └── system_prompt_v1.md                     ← reasoning agent system prompt
│
├── framework/
│   ├── parameter_framework.md         ← 18+ parameter context integration design
│   ├── knowledge_graph_design.md      ← Chromatin Consequence Knowledge Graph spec
│   └── scoring_framework.md           ← Bayesian + conformal prediction design
│
└── figures/
    └── architecture_blueprint.svg     ← visual flowchart of the full pipeline
```

---

## Core architecture components

### 1. Chromatin Consequence Knowledge Graph

A structured knowledge graph where each node is a biological state (a cell cycle phase, a metabolic condition, a specific chromatin modification) and each edge encodes a chromatin-relevant consequence with:

- Organism-specific tags (human vs Drosophila — no unqualified cross-species extrapolation)
- Evidence quality scores based on experimental method, replication count, and recency
- Severity-dependent weights (moderate hypoxia vs severe hypoxia produce quantitatively different JmjC demethylase activity)

The graph is intentionally scoped to human and Drosophila first. Depth and experimental honesty before breadth.

### 2. Parameter Interaction Graph

A curated set of explicitly encoded cross-parameter dependencies — the interactions that make real biological systems behave in ways that single-parameter lookup cannot predict:

- M-phase transcriptional silencing overrides all other pathway activity states
- Hypoxia and IDH mutation compound multiplicatively on JmjC demethylase inhibition, not additively
- Metabolic state and cell cycle interact on shared chromatin targets through overlapping cofactor dependencies

These are not derived by inference — they are encoded as known biological facts, each with a source.

### 3. Epistemic Completeness Checker

Before reasoning begins, the system audits the user's query against the knowledge graph, identifies which parameters are unspecified or poorly characterised in the available literature, and outputs explicit recommendations for what to measure. This turns incomplete knowledge from a hidden flaw into actionable experimental guidance.

A researcher asking about H3K27me3 dynamics in a hypoxic cancer cell line without specifying IDH status, oxygen concentration, or cell cycle synchronisation will be told exactly what additional information would most collapse the mechanistic uncertainty — before a potentially wrong hypothesis is confidently returned.

### 4. Uncertainty propagation

Every output carries confidence distributions reflecting both hypothesis uncertainty and parameter uncertainty simultaneously. The system is explicitly honest about what is well-characterised versus inferred. Mechanisms from Drosophila applied to human queries receive a quantified cross-organism prior. Mechanisms from bulk assay data are flagged when single-cell resolution would change the interpretation.

### 5. Bidirectional scoring

Bayesian joint probability scoring with evidence-weighted adjustment factors, integrated with conformal prediction and entropy balancing for calibrated confidence guarantees. Shannon entropy quantifies residual ambiguity and directly drives the experiment recommendation — the highest-information experiment is the one that most efficiently collapses the entropy of the hypothesis distribution.

---

## Connection to experimental work

This project grew directly out of my work in the Tariq Lab on Ballchen (BALL), the Drosophila H2A T119 kinase and Trithorax group protein. The BALL system is a primary validation case for EpiSignal because it is a genuine bidirectional node:

- **Forward**: upstream signalling activates BALL → H2AT119ph at PRE-proximal loci → displacement of dRING/PRC1 → reduced H2AK118ub1 → derepression of Polycomb target genes
- **Reverse (EpiSignal-generated hypothesis)**: H2AT119ph enrichment at TAD boundary regions may regulate loop extrusion and boundary insulation → affecting which enhancer-promoter pairs are in proximity → controlling signalling gene accessibility → feeding back to the signalling state of the cell

My ChIP-seq data showing Ballchen predominantly localising at insulator elements (dCTCF, CP190, BEAF-32 co-occupancy) is directly relevant to testing this reverse-chain prediction. Hi-C in ball-depleted S2 cells is the experiment EpiSignal would recommend first.

---

## Why this matters now

Frontier AI models are already being used by researchers to reason about chromatin mechanisms. They produce confident, fluent, and partially incorrect answers with no way to distinguish which parts are wrong. The problem is not that researchers are using AI — they are going to use it regardless. The problem is that the AI assistance available to them is untrustworthy for specialist biology at a moment when it could be genuinely useful if built correctly.

EpiSignal is designed to make AI-assisted reasoning in chromatin biology auditable and trustworthy: every claim source-traced, every cross-organism extrapolation explicitly qualified, every confidence score calibrated, every knowledge gap surfaced rather than papered over.

---

## Future directions

**Near term**: Implementation of the core reasoning pipeline for human and Drosophila; integration with PhosphoSitePlus, FlyBase, ENCODE, and 4DN databases; retrospective validation against landmark chromatin biology papers

**Medium term**: Single-cell multi-omics integration replacing categorical parameters with probability distributions learned from scCUT&TAG + scRNA-seq data; expanded organism coverage

**Long term**: Integration with Vector2Variant (Sooknah et al. 2026) for automated GWAS locus to chromatin mechanism reasoning; dynamic chromatin state modelling using ODE systems; prospective wet-lab validation pipeline with prior updating from experimental feedback

Target publication: Genome Biology, Nucleic Acids Research, or Nature Methods

---

## Contact

Mujtaba Ahmed
MS in Biology, LUMS
Tariq Lab — Epigenetics and Chromatin Biology
22140008@lums.edu.pk
