# CA-2026-SUT
Solutions for the practical assignments of the *Computer Architecture (CA)* course, **Spring 2026**,
Computer Engineering Department, **Sharif University of Technology (SUT)**.

## Course Overview
This repository contains my practical work for the CA course at SUT, which covers computer organization
and architecture — from digital logic building blocks up through datapath and control unit design,
memory hierarchy, and pipelining.

Taught with **Logisim** (digital circuit design/simulation) and **Verilog** for the later, more complex
practicals.

The course covers:
- Review of basic computer components and history; combinational/sequential circuits, digital vs. analog,
  multiplexers, decoders, tri-state gates, buses
- Levels of abstraction and computer description; generations of computers
- Number representation: signed/unsigned, fixed/floating point, precision and representable range
- Processor/computer performance: definition, the performance formula, benchmarking
- Datapath and hardwired control design; addressing modes; register-transfer level (RTL); Instruction Set
  Architecture (ISA); step-by-step analysis and design of a sample processor (MIPS); interrupts vs. polling
- Control unit design; microprogrammed control vs. hardwired control, trade-offs; sample architecture case study
- Memory systems: memory hierarchy; cache memory and mapping techniques (direct-mapped, fully associative,
  set-associative)
- Arithmetic algorithms: addition, subtraction, multiplication, division; Booth-encoded and array multipliers
- I/O methods and handshaking
- Advanced architectures: speed-up/parallelization techniques; overview of pipelining and pipeline execution time

## Notes
- **LaTeX template:** All write-ups were typeset with my own reusable Persian/XeLaTeX assignment
  template — see [Persian-LaTeX-Assignment-Template](https://github.com/theQuantaBoy/Persian-LaTeX-Assignment-Template).
  To build any `PHW-N/LaTeX/*.tex` here, drop it into a copy of that template (for its `commons/style.sty`
  and `fonts/`).
- **Judge system:** These practicals were developed and tested against the course's
  [ca4042-judge](https://hamgit.ir/mbahramiand/ca4042-judge) system.

## Information
**Instructor:** Prof. Sarbazi-Azad

**Student:** Mohsen Salah
**Student ID:** 403106238
