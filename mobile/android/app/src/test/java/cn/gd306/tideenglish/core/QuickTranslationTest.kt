package cn.gd306.tideenglish.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class QuickTranslationTest {
    private fun request(text: String, target: String = "Chinese (Simplified)") =
        QuickTranslationRequest(text, "English", target)

    @Test fun rejectsBlankOversizedAndUnsupportedRequests() = runTest {
        var calls = 0
        val controller = QuickTranslationController(backgroundScope, delayMillis = 0) { calls++; "unexpected" }
        for (value in listOf(request(" \n"), request("😀".repeat(1001)), request("Hi", "invented"))) {
            controller.update(value); runCurrent()
        }
        assertEquals(0, calls); assertFalse(controller.isLoading)
    }

    @Test fun debouncesTypingAndPreservesInput() = runTest {
        val inputs = mutableListOf<String>()
        val controller = QuickTranslationController(backgroundScope, delayMillis = 30) {
            inputs += it.text; "  你好！ \n"
        }
        controller.update(request("H")); controller.update(request("  Hello!\n"))
        advanceTimeBy(31); runCurrent()
        assertEquals(listOf("  Hello!\n"), inputs)
        assertEquals("你好！", controller.text); assertFalse(controller.isLoading)
    }

    @Test fun changedLanguageDiscardsLateUncancellableResult() = runTest {
        val finish = CompletableDeferred<String>()
        val controller = QuickTranslationController(backgroundScope, delayMillis = 0) {
            if (it.targetLanguage == "French") "Bonjour" else withContext(NonCancellable) { finish.await() }
        }
        controller.update(request("Hello")); runCurrent()
        controller.update(request("Hello", "French")); runCurrent()
        finish.complete("你好"); runCurrent()
        assertEquals("Bonjour", controller.text)
        controller.reset(); assertEquals("", controller.text)
    }

    @Test fun emptyResponseCanBeRetriedManually() = runTest {
        var calls = 0
        val controller = QuickTranslationController(backgroundScope, delayMillis = 0) { if (++calls == 1) " \n" else "你好" }
        controller.update(request("Hello")); runCurrent()
        assertNotNull(controller.error); assertEquals("", controller.text)
        controller.update(request("Hello"), immediately = true); runCurrent()
        assertNull(controller.error); assertEquals("你好", controller.text)
    }

    @Test fun resetPreventsPendingInputFromBeingSent() = runTest {
        var calls = 0
        val controller = QuickTranslationController(backgroundScope, delayMillis = 20) { calls++; "你好" }
        controller.update(request("Hello")); controller.reset()
        advanceTimeBy(21); runCurrent()
        assertEquals(0, calls); assertFalse(controller.isLoading)
    }

    @Test fun manualTranslationBypassesTypingDelay() = runTest {
        var calls = 0
        val controller = QuickTranslationController(backgroundScope, delayMillis = 10000) { calls++; "你好" }
        controller.update(request("Hello"))
        assertFalse(controller.isLoading)
        controller.update(request("Hello"), immediately = true); runCurrent()
        assertEquals(1, calls); assertEquals("你好", controller.text)
    }
}
