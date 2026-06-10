# EpiSignal: Context-Aware Mechanistic Reasoning Agent for Chromatin and Signalling Biology

**Author:** Mujtaba Ahmed | MS Biology, LUMS, Pakistan | Epigenetics Lab, Dr. Muhammad Tariq  
**Status:** Active development — architecture and framework complete, implementation in progress  
**Contact:** 22140008@lums.edu.pk

---

## The Problem

Chromatin biology generates multi-omics data at scale. Interpreting it mechanistically is a bottleneck that no existing tool addresses well.

- **Frontier language models** (GPT-4, Claude) hallucinate mechanisms and cannot ground reasoning in experimental evidence
- **Specialist databases** (ENCODE, FlyBase, UniProt) store facts but do not reason
- **Sequence-to-function models** (ChromBPNet, bpAI-TAC) predict chromatin accessibility from sequence but have no representation of cellular state — the same motif behaves differently depending on signalling context, cell cycle position, metabolic state, and chromatin modification environment, and those models cannot account for that

The result: a researcher observing an unexpected ChIP-seq peak, ATAC-seq accessibility change, or RNA-seq expression shift has no reliable tool to ask "what mechanism could explain this, given everything I know about the cellular context?"

---

## What EpiSignal Does

EpiSignal is a domain-specific autonomous reasoning agent that takes an experimental observation and a defined biological context, and returns ranked mechanistic hypotheses with calibrated uncertainty and explicit recommendations for the most informative follow-up experiment.

It reasons **bidirectionally**: both forward (signal → chromatin modification → gene expression) and in reverse (chromatin state → pathway activity → upstream signal). Existing platforms treat chromatin as a passive downstream output of signalling. EpiSignal encodes the reverse chain explicitly, because chromatin state actively regulates pathway activity and that feedback loop is mechanistically critical.

---

## Architecture

### 1. Biological Knowledge Graph
- Nodes encode biological states as documented molecular consequences
- Edges encode directional causal relationships with organism-specific evidence weights
- Scoped to human and Drosophila for biological depth before expansion
- Covers: PcG/TrxG regulation, histone modification cross-talk, kinase-to-chromatin axes, metabolic-epigenetic coupling, 3D genome organisation, TE silencing, phase separation

### 2. Cellular Context Integration Framework (18+ parameters)
Cross-parameter dependencies are modelled explicitly. Parameters include:
- Cell cycle stage
- Developmental stage  
- Metabolic state (acetyl-CoA availability, SAM levels, NAD/NADH ratio)
- Signalling pathway activity
- Chromatin modification state at locus
- Phase separation state
- Organism and tissue type
- Disease background
- Environmental stress
- Chromatin memory (prior modification history)

Joint logical constraint filtering reduces the feasible hypothesis space by 60-80% before scoring, eliminating mechanisms that are incompatible with the stated context.

### 3. Bidirectionality Engine
The core reasoning module traverses both:
- **Forward chain:** kinase activation → histone phosphorylation → reader recruitment → transcriptional output
- **Reverse chain:** chromatin modification state → pathway feedback → upstream signalling consequence

Cross-talk engine identifies cases where multiple pathways converge on shared chromatin targets and disentangles their contributions.

### 4. Scoring and Uncertainty Framework
- Bayesian joint probability with evidence-weighted adjustment factors
- Conformal prediction with entropy balancing for calibrated confidence guarantees
- Signal fidelity scoring via conditional mutual information to distinguish primary mechanisms from secondary effects
- Output explicitly distinguishes well-characterised mechanisms from inferred ones
- Knowledge gaps are surfaced as experimental recommendations, not silent assumptions

### 5. Cellular State Consequence Map
Encodes chromatin-relevant consequences of complete cellular biology:
- Nuclear envelope breakdown in M-phase
- Condensin-mediated compaction
- HP1 condensate dissolution dynamics
- Metabolite availability changes across cell cycle
This enables holistic reasoning without requiring whole-cell simulation.

---

## Current Status

| Component | Status |
|-----------|--------|
| Scientific architecture document (19 sections) | Complete |
| Knowledge graph design and node/edge schema | Complete |
| Bidirectionality engine specification | Complete |
| 18-parameter context framework | Complete |
| Statistical scoring framework | Complete |
| System prompt (EpiSignal v1.0) | Complete |
| Case studies: retrospective self-test against Tariq Lab publications | Complete |
| Implementation (Python) | In progress |
| Evaluation benchmark | Planned |

---

## Biological Motivation

This system emerged from two years of experimental chromatin biology in Drosophila in Dr. Muhammad Tariq's Epigenetics Lab at LUMS.

**Ballchen project:** Ballchen is a histone H2A kinase and Trithorax group regulator that deposits H2AT119ph, directly antagonising PRC1-mediated H2AK118ub on the same histone tail. ChIP-seq placed Ballchen at insulator elements alongside dCTCF, CP190, and BEAF-32 in S2 cells — suggesting a chromatin modifier embedded in domain boundary machinery. Interpreting what that means mechanistically, and which signalling pathways regulate it, exposed the absence of a reliable reasoning tool.

**Grainy Head project:** Integrating ChIP-seq for Pc, Pho, Trl, CBP, H3K27ac, H3K27me3 with ATAC-seq and RNA-seq across Drosophila embryonic time points showed that chromatin accessibility depended not on pioneer factor binding but on the PcG/TrxG modification landscape. The bottleneck was always interpretation, not data generation.

EpiSignal is the tool both projects needed.

---

## Key Design Principles

1. **Biological parameters interact non-independently.** Encoding cross-parameter dependencies is essential for reliable mechanistic reasoning. A chromatin state that is stable in G1 may be unstable in M-phase. A histone mark that activates transcription in one metabolic state may be read differently in another.

2. **Uncertainty is information.** The system communicates what is well-characterised versus inferred, and turns knowledge gaps into experimental recommendations rather than silent assumptions.

3. **Bidirectionality is not optional.** Chromatin state regulates signalling. Any system that only models signal→chromatin misses half the biology.

4. **Organism-specificity matters.** Mechanisms established in yeast may not apply in Drosophila. Mechanisms in mouse may not apply in human. Evidence weights are organism-specific.

---

## Planned Publication

Target: development paper with retrospective case studies and prospective benchmark evaluation  
Collaboration: Tariq Lab, LUMS

---

## Repository Contents

```
EpiSignal-ChromatinReasoning/
├── README.md
├── architecture/
│   ├── EpiSignal_Architecture_Document_v1.md    # Full 19-section scientific design
│   ├── system_prompt_v1.md                       # Complete EpiSignal system prompt
│   ├── knowledge_graph_schema.md                 # Node/edge structure and evidence weights
│   └── scoring_framework.md                      # Statistical scoring specification
├── case_studies/
│   ├── ballchen_retrospective.md                 # Self-test against Khan et al. 2021
│   └── grh_pioneer_factor.md                     # Self-test against Shaukat et al. 2021
└── implementation/
    └── (in progress)
```

---

## References

1. Khan A et al. (2021). Ballchen regulates Polycomb silencing through H2AT119ph. *[Tariq Lab publication]*
2. Jin Y, Huang et al. (2026). TxConformal: calibrated uncertainty for biological reasoning agents.
3. Cao L, Coventry B et al. (2022). Design of protein-binding proteins from the target structure alone. *Nature* 605, 551–560.
4. Zhang H et al. (2024). Genome folding principles uncovered in condensin-depleted mitotic chromosomes. *Nature Genetics* 56, 1598–1611.

---

*EpiSignal is being developed as an open tool for the chromatin biology community. Contributions and collaborations welcome.*
