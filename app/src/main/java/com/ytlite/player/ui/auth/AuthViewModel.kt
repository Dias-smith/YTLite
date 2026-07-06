package com.ytlite.player.ui.auth

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AuthViewModel(
    application: Application,
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
) : ViewModel() {

    val session: StateFlow<UserSession?> = authRepository.session
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _showSignInSheet = MutableStateFlow(false)
    val showSignInSheet: StateFlow<Boolean> = _showSignInSheet.asStateFlow()

    val supabaseConfigured: Boolean = authRepository.supabaseConfigured

    init {
        viewModelScope.launch {
            authRepository.initialize()
        }
    }

    fun openSignInSheet() {
        _showSignInSheet.value = true
        authRepository.clearError()
    }

    fun dismissSignInSheet() {
        _showSignInSheet.value = false
    }

    fun onGoogleSignInSuccess(
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        email: String?,
    ) {
        viewModelScope.launch {
            authRepository.onGoogleSignInSuccess(userId, displayName, avatarUrl, email)
            _showSignInSheet.value = false
        }
    }

    fun signOut() {
        viewModelScope.launch {
            authRepository.signOut()
        }
    }

    fun setAuthError(message: String) {
        authRepository.setError(message)
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { AuthViewModel(application) }
        }
    }
}
