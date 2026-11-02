package cn.gd306.tideenglish
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import cn.gd306.tideenglish.core.*
import cn.gd306.tideenglish.network.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
class EmailAccountViewModel(application:Application):AndroidViewModel(application) {
 private val configuration=EmailAccountConfiguration.configured(BuildConfig.TIDE_ENGLISH_EMAIL_ACCOUNTS_ENABLED,BuildConfig.TIDE_ENGLISH_EMAIL_ACCOUNT_API_URL)
 private val controller=configuration?.let { EmailAccountController(EmailAccountClient(it),EmailAccountSessionStore(application,it.storageScope),it.storageScope) }
 val enabled=configuration!=null
 val state=controller?.state?:MutableStateFlow(EmailAccountState()).asStateFlow()
 init {restore()}
 fun restore(){controller?.let { viewModelScope.launch {it.restore()} } }
 fun sendCode(email:String,deleting:Boolean=false){controller?.let { viewModelScope.launch {it.sendCode(email,deleting)} } }
 fun verify(code:String){controller?.let { viewModelScope.launch {it.verify(code)} } }
 fun signOut(){controller?.let { viewModelScope.launch {it.signOut()} } }
 fun invalidateChallenge()=controller?.invalidateChallenge()
 fun cancelDeletion()=controller?.cancelDeletion()
}
