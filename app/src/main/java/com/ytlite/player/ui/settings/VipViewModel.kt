package com.ytlite.player.ui.settings

import android.app.Activity
import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.vip.VipRepository
import com.ytlite.player.data.vip.VipState
import kotlinx.coroutines.flow.StateFlow

class VipViewModel(
    private val repository: VipRepository,
) : ViewModel() {
    val state: StateFlow<VipState> = repository.state

    fun start() = repository.start()

    fun reloadPricing() = repository.reloadPricing()

    fun purchase(activity: Activity, productId: String) =
        repository.launchPurchase(activity, productId)

    fun restore() = repository.restore()

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    VipViewModel(VipRepository.getInstance(application))
                }
            }
    }
}
