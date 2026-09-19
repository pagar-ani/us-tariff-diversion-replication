# Multilateral Tariff Diversion in United States Machinery and Electronics Imports: A Continuous Difference-in-Differences Approach

**Author:** Independent Researcher, Delhi, India  
**Preprint:** SSRN Working Paper (September 2026)  
**Replication Archive:** [https://github.com/pagar-ani/us-tariff-diversion-replication](https://github.com/pagar-ani/us-tariff-diversion-replication)  

---

## Abstract

Evaluating 36 consecutive months of administrative customs declarations across machinery and electronics (Harmonized System Chapters 84 and 85, N = 25,624 across 133 four-digit HS headings), this paper investigates global supply chain reallocation following 2025 United States reciprocal border duties. Under Chapter 99 provisions, advanced computing and telecommunications apparatus entering from non-China partners were exempted from reciprocal tariffs, while Chinese shipments faced cumulative duties exceeding 60%. Implementing a continuous difference-in-differences design using an exogenous pre-panel baseline (ChinaShare_s^2022), we estimate a multilateral diversion elasticity relative to China of β̂_ExChina = 1.4720 (SE = 0.2886, p < 0.0001). Regression discontinuity in time splines and dynamic event studies establish pre-treatment stationarity followed by a discrete enforcement step jump (δ̂ = 1.3673, p < 0.0001). Sourcing reallocation is pervasive across capital goods outside computing and telecommunications apparatus (β̂_NonTech = 1.2095, p = 0.0001). We detect no statistically significant change in landed unit values along the exposure gradient (β̂_P = +0.1181, p = 0.1631), consistent with proportional volume expansion across established overseas assembly hubs.

**JEL Codes:** F13, F14, C23, L63  
**Keywords:** Reciprocal Tariffs, Multilateral Diversion, Continuous DiD, PPML, Exogenous Baseline, Global Value Chains

---

## Repository Structure

This repository contains the replication data, Stata code, and benchmark estimation logs for the empirical results reported in the working paper:

```
├── figure_event_study_2024m12.png             # Dynamic event study chart (Figure 1)
├── README.md                                  # Replication guide and repository documentation
└── replication_package/
    ├── data/
    │   ├── stata/                             # Processed Stata datasets (.dta)
    │   ├── csv/                               # Delimited CSV extracts
    │   └── raw_api_payloads/                  # Raw UN Comtrade API responses (JSON)
    ├── src/
    │   └── stata/                             # Stata estimation scripts (.do)
    └── results/                               # Benchmark Stata estimation logs (.txt)
```

---

## Data Particulars

- **Data Source:** United Nations Comtrade Database (Reporter Code: `842 USA`, imports at 4-digit HS heading level).
- **Scope:** Complete universe of 133 active four-digit classifications in Harmonized System Chapters 84 (machinery and mechanical appliances) and 85 (electrical equipment).
- **Time Horizon:** 36 consecutive calendar months from January 2023 through December 2025 (`2023M01`–`2025M12`).
- **Country Coverage:** China (duty-affected origin), alongside five core alternative assembly hubs: Taiwan, Mexico, Vietnam, Thailand, and India (extended to an 11-country panel in Section 4.9).
- **Sample Size:** 133 × 6 × 36 = 28,728 potential cells; 25,624 positive transaction declarations (N = 25,544 estimation sample excluding singletons; N = 28,353 balanced sample in PPML).

---

## Stata Replication Instructions

All Stata routines use relative file paths. No manual path modifications are required.

### 1. Prerequisites

The estimation routines require Stata 16 or higher (verified on Stata 16 through 19). Prior to running, install the standard packages from SSC if not already present:

```stata
* Install required SSC packages
ssc install ftools, replace
ssc install reghdfe, replace
ssc install ppmlhdfe, replace
ssc install sdid, replace

* Compile Mata libraries
cap ftools, compile
cap reghdfe, compile
mata: mata mlib index
```

### 2. Running the Estimations

To reproduce all estimation results from scratch:

1. Open Stata.
2. Change directory to the Stata source folder:
   ```stata
   cd "replication_package/src/stata"
   ```
3. Execute the master script:
   ```stata
   do "00_master_run_everything.do"
   ```

The master script executes four routines in sequence:
- **`00_data_audit_and_eda.do`:** Data validation checks and summary statistics.
- **`run_all.do`:** Primary continuous DiD and leave-one-out sensitivity tests.
- **`01_multilateral_hs84_hs85_estimation.do`:** Full 133-heading models, PPML levels regressions, and two-way clustered standard errors (Tables 1, 2, and 4).
- **`02_hausman_rapson_rdit_splines.do`:** Regression discontinuity in time splines (Table 3).

### 3. Output Logs

Benchmark estimation logs are saved in `replication_package/results/`:
- `data_audit_and_eda_log.txt`: Data verification and distribution summary.
- `stata_replication_log.txt`: Baseline continuous DiD estimation logs.
- `multilateral_hs84_hs85_log.txt`: Full 133-heading continuous DiD and PPML regressions.
- `rdit_splines_log.txt`: Regression discontinuity in time spline models.
- `wcb_certification_log.txt`: Wild cluster bootstrap test results.

Estimated run-time is approximately 6 to 10 minutes on a standard workstation.

---

## Citation

Suggested citation:

```bibtex
@article{pagarani2026multilateral,
  title={Multilateral Tariff Diversion in United States Machinery and Electronics Imports: A Continuous Difference-in-Differences Approach},
  author={Pagarani},
  journal={SSRN Electronic Journal},
  year={2026},
  note={Working Paper}
}
```

---

## License

- **Code:** MIT License.
- **Data & Documentation:** Creative Commons Attribution 4.0 International (CC-BY-4.0).
