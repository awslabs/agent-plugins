# Clarification Questions (Q1-Q8) & Defaults

## Q1: Migration Timeline

**Question:** How quickly do you need to complete the migration?

**Options:**

- A. Immediate (0-3 months)
- B. Near-term (3-6 months)
- C. Flexible (6-12 months)
- D. No timeline pressure

**Default (Mode C):** C (6-12 months)

---

## Q2: Primary Concern

**Question:** What is your top priority for this migration?

**Options:**

- A. Cost reduction
- B. Technical capability / compliance
- C. Speed to execution
- D. Team familiarity / maintainability

**Default (Mode C):** A (Cost reduction)

---

## Q3: Team Experience

**Question:** What is your team's experience level with AWS?

**Options:**

- A. Expert (deployed 5+ production AWS services)
- B. Moderate (deployed 1-2 AWS services)
- C. Novice (AWS new to team)
- D. Mixed (varies by role)

**Default (Mode C):** C (Novice; assume managed services preferred)

---

## Q4: Traffic Profile

**Question:** What is your typical traffic pattern?

**Options:**

- A. Highly variable (10x-100x spikes)
- B. Predictable (±20% variation)
- C. Mostly steady (±5% variation)
- D. Unknown / hard to predict

**Default (Mode C):** B (Predictable; assume on-demand sizing)

---

## Q5: Database Requirements

**Question:** What type of database access pattern do you need?

**Options:**

- A. Structured (relational, ACID, SQL)
- B. Document-oriented (NoSQL, flexible schema)
- C. Analytics (data warehouse, OLAP)
- D. Mix of above

**Default (Mode C):** A (Structured; RDS Aurora default)

---

## Q6: Cost Sensitivity

**Question:** How cost-sensitive is your migration budget?

**Options:**

- A. Very sensitive (minimize at all costs)
- B. Moderate (balance cost + performance)
- C. Cost not primary (prioritize capability)
- D. Depends on service

**Default (Mode C):** B (Moderate; Balanced tier default)

---

## Q7: Multi-Cloud Strategy

**Question:** Do you plan to keep workloads running on GCP?

**Options:**

- A. No (full exit from GCP)
- B. Yes (multi-cloud for redundancy)
- C. Maybe (undecided)
- D. Yes (strategic GCP usage remains)

**Default (Mode C):** A (Full exit; assume full migration)

---

## Q8: Compliance / Regulatory

**Question:** Do you have specific compliance or regulatory requirements?

**Options:**

- A. None
- B. Standard (HIPAA, PCI-DSS, SOC2)
- C. Strict (FedRAMP, GxP, GDPR)
- D. Varies by service

**Default (Mode C):** A (None)

---

## Mode Summary

| Mode  | Interaction                            | Defaults Used?                                           |
| ----- | -------------------------------------- | -------------------------------------------------------- |
| **A** | User answers all 8 questions at once   | No; use user answers                                     |
| **B** | Agent asks each question separately    | No; use user answers                                     |
| **C** | No questions; use defaults immediately | Yes; Mode C defaults above                               |
| **D** | User provides free-form requirements   | Partial; extract Q1-8 from text, fill gaps with defaults |

---

## Output: clarified.json

See `references/shared/output-schema.md` for the `clarified.json` schema.
