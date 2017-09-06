/*
    Copyright (c) 2017, Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2017
* @group Utilities
* @description Utilities for working with the currency exchange rate organization cahce
*/
public class UTIL_CurrencyCache implements UTIL_CurrencyCache.Interface_x {

    // ====================================================================
    // STATIC VARS USED TO HOLD VALUES THROUGH THE EXECUTION CONTEXT
    // ====================================================================

    @TestVisible
    private static final String LIST_TYPE_EFF_DATES = 'Dates';
    @TestVisible
    private static final String LIST_TYPE_EXCH_RATES = 'Rates';
    @TestVisible
    public static final Date DEFAULT_DATE = Date.newInstance(0001, 1, 1); // 12/30/0000 -- old date to use for standard rates

    /**
     * @description Cache of rates/effective dates by currency iso code
     * Example: 'CAD' => Map<String, List<Object>>{
     *                      'Dates' => List<Date>,
     *                      'Rates' => List<Decimal>
     *                   }
     */
    @TestVisible
    private static Map<String, Map<String, List<Object>>> cachedRatesByCurrency =
            new Map<String, Map<String, List<Object>>>();

    /* Retrieve and cache the household settings the first time this class is loaded only */
    private static final npo02__Households_Settings__c householdSettings = UTIL_CustomSettingsFacade.getHouseholdsSettings();

    // ====================================================================
    // PRIMARY EXPOSED STATIC METHODS
    // ====================================================================

    /**
     * @description Return a specific exchange rate from the cache for the specified currency code and effective date.
     * @param currCode - The currency to retrieve a rate for
     * @param dt - Effective Date to find a rate for (or null to use the current date)
     * @return Exchange Rate
     */
    public static Decimal getEffectiveExchangeRate(String currCode, Date dt) {
        List<Date> effDates = new List<Date>();
        List<Decimal> rates = new List<Decimal>();

        // If the current static var cache does not have a value for the CurrencyCode
        // look in the Platform cache first (if available) and if not retrieve from the database.
        if (!cachedRatesByCurrency.containsKey(currCode)) {
            if (getInstance().isOrgCacheAvailable()) {
                cachedRatesByCurrency.put(currCode, (Map<String, List<Object>>) orgCache.get(CurrencyCache.class, currCode));
            } else {
                cachedRatesByCurrency.put(currCode, getInstance().getRateMapForCurrencies(new List<String>{ currCode }).get(currCode));
            }
        }

        // If a set of rates was retrieved, find the effective rate based on the date
        if (cachedRatesByCurrency.containsKey(currCode)) {
            effDates = (List<Date>) cachedRatesByCurrency.get(currCode).get(LIST_TYPE_EFF_DATES);
            rates = (List<Decimal>) cachedRatesByCurrency.get(currCode).get(LIST_TYPE_EXCH_RATES);

            if (dt == null) {
                dt = Date.Today();
            }

            // The list of effective dates is in descending date order
            for (Integer n = 0; n < effDates.size(); n++) {
                if (dt >= effDates[n]) {
                    return rates[n];
                }
            }
        }

        // TODO: no rate found - now what? Throw an exception maybe; or just return 1?
        return 1;
    }

    /**
     * @description Returns the OrganizationCache object from the UTIL_PlatformCache class
     * or null if there is no npsp org cache available to use.
     */
    public static Cache.OrgPartition orgCache {
        get {
            return UTIL_PlatformCache.orgCache;
        }
    }

    /** @description Store instance for Singleton pattern */
    @TestVisible
    private static Interface_x instance;

    /**
     * @description Get the singleton instance of the UTIL_CurrencyCache class
     * @return UTIL_CurrencyCache.Interface_x
     */
    public static Interface_x getInstance() {
        if (instance == null) {
            instance = new UTIL_CurrencyCache();
        }
        return instance;
    }

    /** @description Private constructor for Singleton pattern */
    @TestVisible
    private UTIL_CurrencyCache() {}

    // ====================================================================
    // CACHEBUILDER CLASS TO MANAGE RETRIEVING/PUTTING ELEMENTS INTO THE CACHE
    // ====================================================================

    /**
     * @description CacheBuilder implementation to retrieve/load dates/rates by currency code
     * CacheBuilder is smart enough to use the values in the cache if they exist and if not it will call the
     * code witin the doLoad() method below to retrieve the values and then store them in the cache so they're
     * available on the next call.
     * However, if the cache isn't available at all, the cachebuilder interface cannot be used.
     */
    public class CurrencyCache implements Cache.CacheBuilder {
        public Map<String, List<Object>> doLoad(String currCode) {
            return getInstance().getRateMapForCurrencies(new List<String>{currCode}).get(currCode);
        }
    }

    // ====================================================================
    // INSTANCE METHODS IN THE INTERFACE AVAILBLE FOR MOCKING IN TESTS
    // ====================================================================

    /**
     * @description public Interface to enable mocking of this class functionality for unit tests in orgs
     * that may or may not have multicurrency and/or platform cache enabled.
     */
    public interface Interface_x {
        Boolean isOrgCacheAvailable();
        void resetCurrencyCache();
        Map<String, Map<String, List<Object>>> getRateMapForCurrencies(List<String> currCodes);
    }

    /**
    * @description Returns true if an organization cache is available
    */
    public boolean isOrgCacheAvailable() {
        return UTIL_PlatformCache.isOrgCacheAvailable();
    }

    /**
     * @description Given a list of currency codes, returns a map of effective dates and related exchange rates
     * pulling from either the CurrencyType or DatedConversionRate object.
     * @param List of currency codes to retrieve data for
     * @return Map<CurrencyCode, Map<ListTypeConstant, List<Date|Decimal>>>
     */
    public Map<String, Map<String, List<Object>>> getRateMapForCurrencies(List<String> currCodes) {
        Map<String, Map<String, List<Object>>> mapOfEffRatesByCurrencyCode
                = new Map<String, Map<String, List<Object>>>();

        // Even if ACM is enabled, the Admin may choose to not use dated conversion rates for roll-ups.
        Boolean useDatedConversionRates = UTIL_Currency.getInstance().isAdvancedCurrencyManagementEnabled()
                && householdSettings.Use_Dated_Conversion_Rates__c == true;

        if (useDatedConversionRates) {
            // When ACM is enabled, query the DatedConversionRate table to retrieve the effective dates
            // but only for the specific currency code requested.
            String soql = 'SELECT IsoCode, ConversionRate, StartDate ' +
                    'FROM DatedConversionRate ' +
                    'WHERE IsoCode IN :currCodes ' +
                    'ORDER By IsoCode, StartDate DESC';
            for (SObject dcr : database.query(soql)) {
                String currCode = (String) dcr.get('IsoCode');
                Map<String, List<Object>> effectiveRatesAndDates = mapOfEffRatesByCurrencyCode.get(currCode);
                if (effectiveRatesAndDates == null) {
                    effectiveRatesAndDates = new Map<String, List<Object>>{
                            LIST_TYPE_EFF_DATES => new List<Date>(),
                            LIST_TYPE_EXCH_RATES => new List<Decimal>()
                    };
                }
                Date dt = (Date) dcr.get('StartDate');
                Decimal rt = (Decimal) dcr.get('ConversionRate');
                if (dt == DEFAULT_DATE) {
                    // Salesforce uses the default date of 1/1/1900 as their oldest date
                    // but we want to use that same date for our default oldest date as well
                    // when dated exchange rates are NOT being used. To work around this
                    // we just add one year to Salesforce's default old date to make it unique.
                    dt = DEFAULT_DATE.addYears(1);
                }
                effectiveRatesAndDates.get(LIST_TYPE_EFF_DATES).add(dt);
                effectiveRatesAndDates.get(LIST_TYPE_EXCH_RATES).add(rt);
                mapOfEffRatesByCurrencyCode.put(currCode, effectiveRatesAndDates);
            }

            // If dated exchange rates are in affect, we still need to capture the 'default'
            // standard rate to use in the specific scenario of determing the exchange rate
            // against the legacy rollups that are based on aggragate soql. Do that by adding one
            // rate to the table with an effective date of 1/1/1900
            soql = 'SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = True' +
                    ' AND IsoCode IN :currCodes';
            for (SObject scr : database.query(soql)) {
                String currCode = (String) scr.get('IsoCode');
                Map<String, List<Object>> effectiveRatesAndDates = mapOfEffRatesByCurrencyCode.get(currCode);
                effectiveRatesAndDates.get(LIST_TYPE_EFF_DATES).add(DEFAULT_DATE);
                effectiveRatesAndDates.get(LIST_TYPE_EXCH_RATES).add((Decimal) scr.get('ConversionRate'));
                mapOfEffRatesByCurrencyCode.put(currCode, effectiveRatesAndDates);
            }

        } else if (UserInfo.isMultiCurrencyOrganization()) {
            // If ACM is not enabled, query the standard rate table and create a single rate
            // instance per currency code for all currency codes with an effective date of 1/1/900.
            String soql = 'SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = True';
            for (SObject scr : database.query(soql)) {
                String currCode = (String) scr.get('IsoCode');
                Map<String, List<Object>> effectiveRatesAndDates = new Map<String, List<Object>>{
                        LIST_TYPE_EFF_DATES => new List<Date>{ DEFAULT_DATE },
                        LIST_TYPE_EXCH_RATES => new List<Decimal>{ (Decimal) scr.get('ConversionRate') }
                };
                mapOfEffRatesByCurrencyCode.put(currCode, effectiveRatesAndDates);
            }
        }
        return mapOfEffRatesByCurrencyCode;
    }

    /**
     * @description Wipe out the org cache for all elements in the CurrencyCache CacheBuilder
     */
    public void resetCurrencyCache() {
        if (isOrgCacheAvailable()) {
            for (String key : orgCache.getKeys()) {
                orgCache.remove(CurrencyCache.class, key);
            }
        }
        UTIL_CurrencyCache.cachedRatesByCurrency.clear();
    }

}