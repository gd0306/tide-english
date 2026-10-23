package cn.gd306.tideenglish
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import cn.gd306.tideenglish.core.*
import cn.gd306.tideenglish.network.*
import kotlinx.coroutines.launch
class EmailAccountViewModel(application:Application):AndroidViewModel(application) {
 private val configuration=EmailAccountConfiguration()
 private val controller=EmailAccountController(EmailAccountClient(configuration),EmailAccountSessionStore(application,configuration.storageScope),configuration.storageScope)
 val state=controller.state
 init {viewModelScope.launch {controller.restore()} }
 fun restore(){viewModelScope.launch {controller.restore()} }
 fun sendCode(email:String,deleting:Boolean=false){viewModelScope.launch {controller.sendCode(email,deleting)} }
 fun verify(code:String){viewModelScope.launch {controller.verify(code)} }
 fun signOut(){viewModelScope.launch {controller.signOut()} }
 fun invalidateChallenge()=controller.invalidateChallenge()
 fun cancelDeletion()=controller.cancelDeletion()
}
