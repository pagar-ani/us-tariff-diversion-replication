* ==============================================================================
* DATASET HARMONIZATION UTILITY: SSRN-6477740
* Purpose: Ensures trade_value_m_usd and net_mass_mt are permanently saved on disk
* ==============================================================================

clear all
set more off

* Resilient path navigation
cap confirm file "panel_hs84_hs85_full_universe.dta"
if _rc != 0 {
    cap cd "../../data/stata"
    if _rc != 0 {
        cap cd "data/stata"
        if _rc != 0 {
            cap cd "replication_package/data/stata"
        }
    }
}

* 1. Harmonize Full Universe Positive Flows Panel
cap confirm file "panel_hs84_hs85_full_universe.dta"
if _rc == 0 {
    use "panel_hs84_hs85_full_universe.dta", clear
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        gen double trade_value_m_usd = val_usd / 1000000
    }
    cap confirm variable net_mass_mt
    if _rc != 0 {
        gen double net_mass_mt = mass_kg / 1000
    }
    cap confirm variable post
    if _rc != 0 {
        gen byte post = (period >= 202504)
    }
    save "panel_hs84_hs85_full_universe.dta", replace
    di as res "[SUCCESS] panel_hs84_hs85_full_universe.dta harmonized and saved."
}

* 2. Harmonize Balanced Panel with True Zeros
cap confirm file "panel_hs84_hs85_balanced_with_zeros.dta"
if _rc == 0 {
    use "panel_hs84_hs85_balanced_with_zeros.dta", clear
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        gen double trade_value_m_usd = val_usd / 1000000
    }
    cap confirm variable post
    if _rc != 0 {
        gen byte post = (period >= 202504)
    }
    save "panel_hs84_hs85_balanced_with_zeros.dta", replace
    di as res "[SUCCESS] panel_hs84_hs85_balanced_with_zeros.dta harmonized and saved."
}

di as res "Harmonization complete. All datasets ready for estimation."
