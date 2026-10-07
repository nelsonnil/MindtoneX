# Song search storefront (FAQ)

**What is this setting?**  
It chooses which **Apple iTunes / Apple Music catalog country** MindtoneX searches for 30-second song previews. It is **not** the language of the MindtoneX app UI.

**Automatic (iPhone region)**  
Uses the country/region from **Settings → General → Language & Region** on the iPhone. This is the default and works for most performers.

**When to pick a storefront manually**  
If previews or search results match the wrong market (e.g. Arabic UI language but a US catalog, or a song only listed in Saudi Arabia), open **Home → Performance settings → Song search storefront**, search by country name or ISO code (**SA**, **AE**, **EG**, etc.), and select the catalog you need.

**Fallback**  
If Apple has no preview in the chosen storefront, MindtoneX tries **US**, then **Deezer** automatically.

**Technical note**  
The list matches Apple’s iTunes Search API storefronts (ISO 3166-1 alpha-2 `country` parameter). Source data: [jcoester/iTunes-country-codes](https://github.com/jcoester/iTunes-country-codes) (184 storefronts as of import).
