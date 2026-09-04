package com.ytlite.player.data.vip

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

enum class VipBillingPeriod {
    YEAR,
    MONTH,
    WEEK,
    OTHER,
}

data class VipUiProduct(
    val productId: String,
    val title: String,
    /** Current charge amount (intro / offer / base). */
    val formattedPrice: String,
    /** Billing period for [formattedPrice] from Play (not inferred from product id). */
    val pricePeriod: VipBillingPeriod,
    val strikethroughPrice: String? = null,
    val thenPrice: String? = null,
    val thenPeriod: VipBillingPeriod? = null,
    val savePercent: Int? = null,
    val offerToken: String,
    val isFreeTrial: Boolean = false,
)

data class VipState(
    val isVipActive: Boolean = false,
    val activeProductId: String? = null,
    val products: List<VipUiProduct> = emptyList(),
    val isLoading: Boolean = false,
    val isPurchasing: Boolean = false,
    val errorMessage: String? = null,
)

/**
 * Play Billing VIP entitlement. Primary benefit today: ad-free (when ads ship on Android).
 * Console filter: `YTLite.VIP`
 */
class VipRepository private constructor(context: Context) : PurchasesUpdatedListener {

    private val appContext = context.applicationContext
    private val _state = MutableStateFlow(VipState())
    val state: StateFlow<VipState> = _state.asStateFlow()

    private var productDetailsById: Map<String, ProductDetails> = emptyMap()
    private var lastLoggedStatusKey: String? = null

    private val billingClient: BillingClient = BillingClient.newBuilder(appContext)
        .setListener(this)
        .enablePendingPurchases()
        .build()

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        Log.i(
            TAG,
            "[purchases.updated] code=${result.responseCode} " +
                "msg=${result.debugMessage} count=${purchases?.size ?: 0}",
        )
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                handlePurchases(purchases.orEmpty(), source = "purchase_flow")
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                Log.i(TAG, "[purchase.cancel]")
                _state.update { it.copy(isPurchasing = false) }
            }
            else -> {
                Log.w(
                    TAG,
                    "[purchase.fail] code=${result.responseCode} msg=${result.debugMessage}",
                )
                _state.update {
                    it.copy(
                        isPurchasing = false,
                        errorMessage = "Purchase failed (${result.responseCode})",
                    )
                }
            }
        }
    }

    fun start() {
        if (billingClient.isReady) {
            Log.i(TAG, "[billing.ready] refresh")
            refresh()
            return
        }
        Log.i(TAG, "[billing.connect.start]")
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    Log.i(TAG, "[billing.connect.ok]")
                    refresh()
                } else {
                    Log.w(
                        TAG,
                        "[billing.connect.fail] code=${result.responseCode} " +
                            "msg=${result.debugMessage}",
                    )
                    _state.update {
                        it.copy(errorMessage = "Billing unavailable (${result.responseCode})")
                    }
                }
            }

            override fun onBillingServiceDisconnected() {
                Log.w(TAG, "[billing.disconnected]")
            }
        })
    }

    /** Re-query Play Billing product details whenever the VIP paywall is shown. */
    fun reloadPricing() {
        Log.i(TAG, "[paywall.open]")
        refresh()
    }

    fun refresh() {
        if (!billingClient.isReady) {
            Log.i(TAG, "[refresh] billing not ready → start()")
            start()
            return
        }
        Log.i(TAG, "[refresh.start]")
        _state.update { it.copy(isLoading = true, errorMessage = null) }
        queryProducts()
        queryPurchases()
    }

    fun launchPurchase(activity: Activity, productId: String) {
        val details = productDetailsById[productId] ?: run {
            Log.w(TAG, "[purchase.start.fail] product not loaded id=$productId")
            _state.update { it.copy(errorMessage = "Product not loaded") }
            return
        }
        val offerToken = _state.value.products.firstOrNull { it.productId == productId }?.offerToken
            ?: pickPurchaseOffer(details)?.offerToken
            ?: run {
                Log.w(TAG, "[purchase.start.fail] offer unavailable id=$productId")
                _state.update { it.copy(errorMessage = "Offer unavailable") }
                return
            }
        Log.i(TAG, "[purchase.start] product=$productId")
        _state.update { it.copy(isPurchasing = true, errorMessage = null) }
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .setOfferToken(offerToken)
                        .build(),
                ),
            )
            .build()
        val result = billingClient.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            Log.w(
                TAG,
                "[purchase.launch.fail] code=${result.responseCode} msg=${result.debugMessage}",
            )
            _state.update {
                it.copy(
                    isPurchasing = false,
                    errorMessage = "Purchase failed (${result.responseCode})",
                )
            }
        }
    }

    fun restore() {
        Log.i(TAG, "[restore.start]")
        refresh()
    }

    fun isVipActive(): Boolean = _state.value.isVipActive

    private fun queryProducts() {
        val productList = VipProductIds.ALL.map { id ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(id)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()
        Log.i(TAG, "[products.load.start] ids=${VipProductIds.ALL.joinToString(",")}")
        billingClient.queryProductDetailsAsync(params) { result, productDetailsList ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                Log.w(
                    TAG,
                    "[products.load.fail] code=${result.responseCode} msg=${result.debugMessage}",
                )
                _state.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Products unavailable (${result.responseCode})",
                    )
                }
                return@queryProductDetailsAsync
            }
            val list = productDetailsList.orEmpty()
            productDetailsById = list.associateBy { it.productId }
            val uiProducts = list.mapNotNull { details -> toUiProduct(details) }
                .sortedBy { rank(it.productId) }
            val missing = VipProductIds.ALL.filter { id -> uiProducts.none { it.productId == id } }
            Log.i(
                TAG,
                "[products.load.ok] count=${uiProducts.size}" +
                    if (missing.isEmpty()) "" else " missing=${missing.joinToString(",")}",
            )
            _state.update {
                it.copy(products = uiProducts, isLoading = false, errorMessage = null)
            }
        }
    }

    private fun toUiProduct(details: ProductDetails): VipUiProduct? {
        val offers = details.subscriptionOfferDetails.orEmpty()
        if (offers.isEmpty()) {
            Log.w(TAG, "[products.item] id=${details.productId} offers=empty")
            return null
        }

        logOffers(details.productId, offers)

        val baseOffer = offers.firstOrNull { it.offerId == null }
        val basePhase = baseOffer?.pricingPhases?.pricingPhaseList?.lastOrNull()
        val purchaseOffer = pickPurchaseOffer(details) ?: return null
        val phases = purchaseOffer.pricingPhases.pricingPhaseList
        val current = phases.firstOrNull() ?: return null
        val recurring = basePhase
            ?: phases.lastOrNull()
            ?: current

        val hasIntro = phases.size > 1 &&
            current.priceAmountMicros != recurring.priceAmountMicros
        val isFreeTrial = hasIntro && current.priceAmountMicros == 0L
        val savePercent = when {
            isFreeTrial -> 100
            hasIntro && recurring.priceAmountMicros > 0 -> {
                val saved = ((recurring.priceAmountMicros - current.priceAmountMicros) * 100) /
                    recurring.priceAmountMicros
                saved.toInt().takeIf { it in 1..99 }
            }
            else -> null
        }

        Log.i(
            TAG,
            "[products.item] id=${details.productId} price=${current.formattedPrice} " +
                "intro=$hasIntro freeTrial=$isFreeTrial save=$savePercent",
        )

        return VipUiProduct(
            productId = details.productId,
            title = details.title,
            formattedPrice = current.formattedPrice,
            pricePeriod = billingPeriod(current.billingPeriod)
                ?: fallbackPeriod(details.productId),
            strikethroughPrice = if (hasIntro) recurring.formattedPrice else null,
            thenPrice = if (hasIntro) recurring.formattedPrice else null,
            thenPeriod = if (hasIntro) {
                billingPeriod(recurring.billingPeriod) ?: fallbackPeriod(details.productId)
            } else {
                null
            },
            savePercent = savePercent,
            offerToken = purchaseOffer.offerToken,
            isFreeTrial = isFreeTrial,
        )
    }

    /**
     * Prefer a paid introductory offer the user is eligible for; then free trial; then base plan.
     * Never pick by "cheapest across all phases" alone — that can select the wrong base plan.
     */
    private fun pickPurchaseOffer(
        details: ProductDetails,
    ): ProductDetails.SubscriptionOfferDetails? {
        val offers = details.subscriptionOfferDetails.orEmpty()
        if (offers.isEmpty()) return null

        val base = offers.firstOrNull { it.offerId == null }
        val basePrice = base?.pricingPhases?.pricingPhaseList?.lastOrNull()?.priceAmountMicros
        val discountOffers = offers.filter { !it.offerId.isNullOrBlank() }

        val paidIntro = discountOffers
            .filter { offer ->
                val phases = offer.pricingPhases.pricingPhaseList
                val first = phases.firstOrNull() ?: return@filter false
                val recurring = phases.lastOrNull() ?: first
                val compareAt = basePrice ?: recurring.priceAmountMicros
                first.priceAmountMicros > 0L && first.priceAmountMicros < compareAt
            }
            .minByOrNull { it.pricingPhases.pricingPhaseList.first().priceAmountMicros }
        if (paidIntro != null) return paidIntro

        val freeTrial = discountOffers.firstOrNull { offer ->
            offer.pricingPhases.pricingPhaseList.firstOrNull()?.priceAmountMicros == 0L
        }
        if (freeTrial != null) return freeTrial

        return base ?: offers.firstOrNull()
    }

    private fun logOffers(
        productId: String,
        offers: List<ProductDetails.SubscriptionOfferDetails>,
    ) {
        val summary = offers.joinToString(" | ") { offer ->
            val phases = offer.pricingPhases.pricingPhaseList.joinToString(",") { phase ->
                "${phase.formattedPrice}@${phase.billingPeriod}"
            }
            "base=${offer.basePlanId} offer=${offer.offerId} phases=[$phases]"
        }
        Log.d(TAG, "[pricing] product=$productId -> $summary")
    }

    private fun queryPurchases() {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                handlePurchases(purchases, source = "query")
            } else {
                Log.w(
                    TAG,
                    "[entitlement.query.fail] code=${result.responseCode} " +
                        "msg=${result.debugMessage}",
                )
            }
            _state.update { it.copy(isPurchasing = false, isLoading = false) }
        }
    }

    private fun handlePurchases(purchases: List<Purchase>, source: String) {
        val active = purchases.firstOrNull { purchase ->
            purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                purchase.products.any { it in VipProductIds.ALL }
        }
        if (active != null && !active.isAcknowledged) {
            Log.i(TAG, "[acknowledge.start] products=${active.products} source=$source")
            acknowledge(active)
        }
        val productId = active?.products?.firstOrNull { id -> id in VipProductIds.ALL }
        _state.update {
            it.copy(
                isVipActive = active != null,
                activeProductId = productId,
                isPurchasing = false,
            )
        }
        val statusKey = "${active != null}|${productId ?: "-"}|$source"
        if (statusKey != lastLoggedStatusKey) {
            lastLoggedStatusKey = statusKey
            Log.i(
                TAG,
                "[entitlement.refresh.ok] active=${active != null} " +
                    "product=$productId source=$source",
            )
        } else {
            Log.d(TAG, "[entitlement.refresh.ok] unchanged active=${active != null}")
        }
        if (source == "purchase_flow" && active != null) {
            Log.i(TAG, "[purchase.success] product=$productId")
        }
    }

    private fun acknowledge(purchase: Purchase) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        billingClient.acknowledgePurchase(params) { result ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                Log.i(TAG, "[acknowledge.ok]")
            } else {
                Log.w(
                    TAG,
                    "[acknowledge.fail] code=${result.responseCode} msg=${result.debugMessage}",
                )
            }
        }
    }

    private fun rank(id: String): Int = when (id) {
        VipProductIds.YEARLY -> 0
        VipProductIds.MONTHLY -> 1
        else -> 99
    }

    companion object {
        private const val TAG = "YTLite.VIP"

        @Volatile
        private var instance: VipRepository? = null

        fun getInstance(context: Context): VipRepository =
            instance ?: synchronized(this) {
                instance ?: VipRepository(context).also { instance = it }
            }

        fun billingPeriod(iso8601: String?): VipBillingPeriod? = when (iso8601) {
            "P1Y" -> VipBillingPeriod.YEAR
            "P1M" -> VipBillingPeriod.MONTH
            "P1W" -> VipBillingPeriod.WEEK
            else -> null
        }

        fun fallbackPeriod(productId: String): VipBillingPeriod = when (productId) {
            VipProductIds.YEARLY -> VipBillingPeriod.YEAR
            else -> VipBillingPeriod.MONTH
        }
    }
}
