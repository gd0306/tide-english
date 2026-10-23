package cn.gd306.tideenglish.ui

import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.password
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogWindowProvider
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderConfiguration

@Composable
fun ModelConfigurationDialog(vm: TideEnglishViewModel, onDismiss: () -> Unit) {
    var provider by remember { mutableStateOf(vm.modelConfiguration.provider) }
    var model by remember { mutableStateOf(vm.modelConfiguration.model) }
    var baseURL by remember { mutableStateOf(vm.modelConfiguration.baseURL) }
    var key by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = { key = ""; onDismiss() }) {
        val view = LocalView.current
        DisposableEffect(view) {
            val window = (view.parent as? DialogWindowProvider)?.window
            val secure = (window?.attributes?.flags?.and(WindowManager.LayoutParams.FLAG_SECURE) ?: 0) != 0
            window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            onDispose { if (!secure) window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
        }
        Surface(shape = MaterialTheme.shapes.large) {
            Column(Modifier.padding(22.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(uiText("Model & API key", "模型与 API 密钥"), style = MaterialTheme.typography.headlineSmall)
                SettingsChoiceRow(uiText("Provider", "服务商"), provider.displayName, provider.name,
                    ModelProvider.entries.map { it.name to it.displayName }, "model-provider", !vm.isRunning) { selected ->
                    provider = ModelProvider.valueOf(selected)
                    model = provider.defaultModel
                    baseURL = provider.defaultBaseURL
                    key = ""; error = false
                }
                TideEnglishTextField(model, { model = it.take(200); error = false }, label = { Text(uiText("Chat model", "聊天模型")) }, enabled = !vm.isRunning,
                    modifier = Modifier.fillMaxWidth().testTag("model-name"), singleLine = true)
                if (provider == ModelProvider.CUSTOM) TideEnglishTextField(baseURL, { baseURL = it.take(2048); key = ""; error = false },
                    label = { Text(uiText("HTTPS base URL", "HTTPS 基础地址")) }, enabled = !vm.isRunning, modifier = Modifier.fillMaxWidth().testTag("model-base-url"), singleLine = true)
                Text(uiText("Keys stay encrypted on this device. Each provider and custom endpoint has its own key.", "密钥仅加密保存在此设备。每个服务商和自定义地址使用独立密钥。"), style = MaterialTheme.typography.bodySmall)
                TideEnglishTextField(key, { key = it.take(4096) }, label = { Text(uiText("New API key (optional)", "新 API 密钥（可选）")) },
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false), enabled = !vm.isRunning,
                    modifier = Modifier.fillMaxWidth().testTag("api-key-input").semantics { password() }, singleLine = true)
                if (error) Text(uiText("Check the model, HTTPS endpoint and key, then try again.", "请检查模型、HTTPS 地址和密钥后重试。"), color = MaterialTheme.colorScheme.error)
                if (provider == vm.modelConfiguration.provider && baseURL == vm.modelConfiguration.baseURL && vm.hasKey)
                    TideEnglishTextButton(onClick = { vm.deleteKey(); key = "" }, enabled = !vm.isRunning) { Text(uiText("Remove saved key", "移除已保存密钥")) }
                Text(uiText("OpenAI, Gemini and GLM support native voice. When native access is unavailable, the same selected provider can use device speech recognition and playback. DeepSeek and Custom use device voice.", "OpenAI、Gemini 和 GLM 支持原生语音。原生访问不可用时，可由同一所选服务商配合设备语音识别和朗读。DeepSeek 和自定义服务使用设备语音。"), style = MaterialTheme.typography.bodySmall)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TideEnglishTextButton(modifier = Modifier.testTag("model-config-cancel"), onClick = { key = ""; onDismiss() }) { Text(uiText("Cancel", "取消")) }
                    Button(modifier = Modifier.testTag("model-config-save"), enabled = !vm.isRunning, onClick = {
                        runCatching {
                            val configuration = ProviderConfiguration(provider, model.trim(), baseURL.trim()).validated()
                            if (key.isNotBlank()) ProviderConfiguration.validatedCredential(key.trim())
                            check(vm.updateModelConfiguration(configuration))
                            if (key.isNotBlank()) vm.saveKey(key.trim(), true)
                        }.onSuccess { key = ""; onDismiss() }.onFailure { error = true }
                    }) { Text(uiText("Save", "保存")) }
                }
            }
        }
    }
}
