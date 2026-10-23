package cn.gd306.tideenglish.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cn.gd306.tideenglish.EmailAccountViewModel
import cn.gd306.tideenglish.core.EmailAccountFailure
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun EmailAccountSheet(viewModel:EmailAccountViewModel=androidx.lifecycle.viewmodel.compose.viewModel(),chinese:Boolean=false,onDismiss:()->Unit) {
 val state by viewModel.state.collectAsStateWithLifecycle()
 var email by remember {mutableStateOf(state.pendingEmail.orEmpty())}; var code by remember {mutableStateOf("")}; var confirmDelete by remember {mutableStateOf(false)}
 var now by remember {mutableLongStateOf(System.currentTimeMillis()/1000)}
 LaunchedEffect(Unit){viewModel.restore();while(true){now=System.currentTimeMillis()/1000;delay(1000)}}
 fun t(en:String,zh:String)=if(chinese)zh else en
 ModalBottomSheet(onDismissRequest=onDismiss){Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal=24.dp).padding(bottom=32.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
  Text(t("Tide English account","Tide English 账号"),style=MaterialTheme.typography.headlineSmall)
  Text(t("Optional email sign-in. Learning records and model keys stay on this device. This does not sync learning records.","邮箱登录为可选功能。学习记录和模型密钥保留在本机，不会同步学习记录。"),style=MaterialTheme.typography.bodyMedium)
  state.email?.let {Text(it,style=MaterialTheme.typography.titleMedium)}
  if(state.email==null)OutlinedTextField(value=email,onValueChange={email=it;code="";viewModel.invalidateChallenge()},enabled=!state.busy,label={Text(t("Email","邮箱"))},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Email),modifier=Modifier.fillMaxWidth())
  if(state.email==null||state.deleting){
   if(state.deleting)Text(t("A fresh email code is required to permanently delete your account. Local learning and model keys will stay on this device.","永久删除账号需要新的邮箱验证码。本机学习记录和模型密钥将保留。"))
   val wait=(state.retryAt-now).coerceAtLeast(0)
   OutlinedButton(onClick={code="";viewModel.sendCode(email,state.deleting)},enabled=!state.busy&&wait==0L,modifier=Modifier.fillMaxWidth()){Text(if(wait>0)t("Resend in ${wait}s","${wait} 秒后可重发") else t("Send email code","发送邮箱验证码"))}
   if(state.challengeReady){OutlinedTextField(value=code,onValueChange={code=it.filter { c->c in '0'..'9' }.take(6)},enabled=!state.busy,label={Text(t("6-digit code","六位验证码"))},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.NumberPassword),modifier=Modifier.fillMaxWidth());Button(onClick={viewModel.verify(code);code=""},enabled=!state.busy&&code.length==6&&now<state.challengeExpiresAt,modifier=Modifier.fillMaxWidth()){Text(if(state.deleting)t("Delete account permanently","永久删除账号") else t("Sign in","登录"))}}
   if(state.deleting)TextButton(onClick={viewModel.cancelDeletion();code=""},enabled=!state.busy){Text(t("Cancel deletion","取消删除"))}
  }else {
   OutlinedButton(onClick={viewModel.signOut()},enabled=!state.busy,modifier=Modifier.fillMaxWidth()){Text(t("Sign out","退出登录"))}
   TextButton(onClick={confirmDelete=true},enabled=!state.busy){Text(t("Delete account…","删除账号…"),color=MaterialTheme.colorScheme.error)}
  }
  state.failure?.let {Text(accountMessage(it,chinese),color=MaterialTheme.colorScheme.error)}
  state.completed?.let { Text(when(it){"signedIn"->t("Signed in.","已登录。");"deleted"->t("Account deleted. Local learning and model keys are preserved.","账号已删除。本机学习记录和模型密钥已保留。");else->t("Signed out. Local learning and model keys are preserved.","已退出登录。本机学习记录和模型密钥已保留。")}) }
  if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
  TextButton(onClick=onDismiss,modifier=Modifier.testTag("email-account-done")){Text(t("Done","完成"))}
 }}
 if(confirmDelete)AlertDialog(onDismissRequest={confirmDelete=false},title={Text(t("Delete account?","删除账号？"))},text={Text(t("This permanently deletes the email account. Request a new code to confirm. Your local learning and model keys are preserved.","这将永久删除邮箱账号。需要请求新的验证码以确认。本机学习记录和模型密钥将保留。"))},confirmButton={TextButton(onClick={confirmDelete=false;code="";viewModel.sendCode("",true)}){Text(t("Send deletion code","发送删除验证码"))}},dismissButton={TextButton(onClick={confirmDelete=false}){Text(t("Cancel","取消"))}})
}
private fun accountMessage(f:EmailAccountFailure,zh:Boolean):String { val pair=when(f){
 EmailAccountFailure.InvalidEmail->"Enter a valid email address." to "请输入有效邮箱。"
 EmailAccountFailure.InvalidCode->"That code is invalid or expired. Request a new code." to "验证码无效或已过期，请重新获取。"
 EmailAccountFailure.InvalidSession->"Your session expired. Sign in again." to "登录已过期，请重新登录。"
 EmailAccountFailure.RateLimited->"Wait a minute before trying again." to "请稍等一分钟后重试。"
 EmailAccountFailure.DeliveryUnavailable->"Email could not be sent. Try again later." to "邮件发送失败，请稍后重试。"
 EmailAccountFailure.Transport->"Could not reach the account service. Check your connection." to "无法连接账号服务，请检查网络。"
 EmailAccountFailure.SecureStorage->"Could not securely save or remove the session. Unlock your device and try again." to "无法安全保存或移除登录信息，请解锁设备后重试。"
 EmailAccountFailure.RenewalUncertain->"Session renewal could not be confirmed. Sign in again. Local learning and model keys are preserved." to "无法确认登录续期，请重新登录。本机学习记录和模型密钥已保留。"
 EmailAccountFailure.RevocationUnconfirmed->"Signed out locally. Remote revocation could not be confirmed. Local learning and model keys are preserved." to "已退出本机登录，但无法确认远程会话撤销。本机学习记录和模型密钥已保留。"
 EmailAccountFailure.InvalidResponse->"The account service returned an invalid response. Try again." to "账号服务响应无效，请重试。"
 else->"Account service is unavailable. Try again later." to "账号服务暂时不可用，请稍后重试。"
 };return if(zh)pair.second else pair.first }
