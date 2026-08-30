QTD_HOUSEHOLD = 100
QTD_COMPANY = 10
QTD_STORE = 10
QTD_ADMIN = 3

TOTAL_PROFILES = QTD_HOUSEHOLD + QTD_COMPANY + QTD_STORE + QTD_ADMIN

fim_household = 1 + QTD_HOUSEHOLD
fim_company   = fim_household + QTD_COMPANY
fim_store     = fim_company + QTD_STORE
fim_admin     = fim_store + QTD_ADMIN

RANGES = {
    "household": range(1, fim_household ),
    "company": range(fim_household, fim_company),
    "store": range(fim_company, fim_store),
    "admin": range(fim_store, fim_admin),
}

