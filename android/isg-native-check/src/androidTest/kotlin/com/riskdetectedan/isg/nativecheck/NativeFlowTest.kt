package com.riskdetectedan.isg.nativecheck

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class NativeFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private fun node(id: String) = compose.onNodeWithTag(id)
    private fun exists(id: String) = compose.onAllNodesWithTag(id).fetchSemanticsNodes().isNotEmpty()
    private fun wait(id: String) { compose.waitUntil("Missing $id", 30000) { exists(id) } }
    private fun tap(id: String) {
        compose.waitUntil("Enabled $id", 30000) { compose.onAllNodes(hasTestTag(id) and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        runCatching { node(id).performScrollTo() }; node(id).performClick()
    }
    private fun state(text: String) { compose.waitUntil(30000) { compose.onAllNodes(hasTestTag("qa.state") and hasText(text, substring=true)).fetchSemanticsNodes().isNotEmpty() } }
    private fun field(id: String, value: String) { wait(id); node(id).performScrollTo().performTextReplacement(value); androidx.test.espresso.Espresso.closeSoftKeyboard() }
    private fun find() {
        field("personnel.search","Native android")
        compose.waitUntil(30000) { compose.onAllNodesWithText("Native android", substring=true).fetchSemanticsNodes().size >= 2 }
        compose.onNode(hasClickAction() and hasText("Native android", substring=true) and !hasTestTag("personnel.search")).performScrollTo().performClick()
    }
    private fun directory(kind: String) { tap("qa.directory"); tap("qa.directory.$kind"); state("$kind|idle"); tap("directory.add") }
    private fun choose(field: String,title: String) {
        tap("directory.field.$field")
        val option=hasText(title,substring=true) and hasClickAction() and SemanticsMatcher("Option for $field") {
            it.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.TestTag)?.startsWith("directory.option.$field.")==true
        }
        compose.waitUntil("Option $field: $title",30000){compose.onAllNodes(option).fetchSemanticsNodes().isNotEmpty()}
        compose.onNode(option).performScrollTo().performClick()
    }
    private fun saveDirectory() { tap("directory.save"); wait("directory.add") }
    private fun directoryMatrix(phase: String) {
        if(phase=="catalogs") {
            for((kind,name) in listOf("workplaces" to "workplace","departments" to "department","jobs" to "job","contractors" to "contractor")) {
                directory(kind);field("directory.field.name","Native android $name")
                if(kind=="departments")choose("workplace_id","Native android workplace")
                saveDirectory()
            }
        } else if(phase=="contexts") {
            directory("engagements");choose("organization_id","Native android contractor");choose("workplace_id","Native android workplace")
            field("directory.field.starts_on","2026-01-01");field("directory.field.ends_before","2026-01-01")
            tap("directory.save"); node("directory.field.ends_before").assertExists()
            field("directory.field.ends_before","2027-01-01");saveDirectory()
            for((day,previous) in listOf("2026-01-01" to false,"2026-06-01" to true)) {
                directory("contexts");field("directory.field.starts_on",day)
                if(previous)choose("previous_id","TR")
                field("directory.field.timezone","Europe/Istanbul");field("directory.field.jurisdiction","TR")
                choose("hazard_class","Az tehlikeli");field("directory.field.evidence_note","Native QA context")
                if(previous){field("directory.field.starts_on","2026-01-01");tap("directory.save");node("directory.field.starts_on").assertExists();field("directory.field.starts_on",day)}
                saveDirectory()
            }
        } else if(phase=="assignments" || phase=="assignment_transition") {
            val periods=if(phase=="assignment_transition")listOf("2026-06-01" to true) else listOf("2026-01-01" to false,"2026-06-01" to true)
            for((day,previous) in periods) {
                directory("assignments");choose("workplace_id","Native android workplace");choose("department_id","Native android department");choose("job_role_id","Native android job")
                field("directory.field.starts_on",day);if(previous){choose("previous_id","Native android job");field("directory.field.starts_on","2026-01-01");tap("directory.save");node("directory.field.starts_on").assertExists();field("directory.field.starts_on",day)}
                saveDirectory()
            }
            directory("employers");choose("organization_id","Native android contractor");saveDirectory()
        }
    }
    @Test fun realNativeLifecycle() {
        val registry = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        val intent = Intent(registry.targetContext, NativeActivity::class.java).putExtra("url",args.getString("url")).putExtra("key",args.getString("key")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<NativeActivity>(intent).use { scenario ->
            state("ready|idle"); tap("qa.company.a"); wait("personnel.add")
            val phase=args.getString("phase")!!
            if(phase=="foreground") {
                lateinit var activity: NativeActivity
                scenario.onActivity{activity=it}
                for(action in listOf("write_off","paid_off","read_off")) {
                    scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
                    runBlocking{activity.qa("control",action)}
                    scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED);state("|idle|readonly")
                    if(action=="read_off")node("personnel.add").assertDoesNotExist() else node("personnel.add").assertIsNotEnabled()
                    scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
                    runBlocking{activity.qa("control","reset")}
                    scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED);state("|idle|write")
                }
                return
            }
            if(phase in listOf("catalogs","contexts","assignments","assignment_transition")){directoryMatrix(phase);return}
            if(args.getString("phase")=="prepare") {
                tap("qa.drop_next"); state("drop_next|idle")
                tap("personnel.add"); field("personnel.name","Native android"); field("personnel.department","Native android departman")
                tap("personnel.save"); wait("personnel.retry")
                return
            }
            if(phase=="complete") {
            wait("personnel.recover"); node("personnel.add").assertIsNotEnabled()
            tap("qa.reset"); state("reset|idle|write"); tap("personnel.recover")
            wait("personnel.edit")
            tap("personnel.edit"); field("personnel.name","Native android Son"); tap("personnel.save")
            tap("personnel.edit"); tap("personnel.archive"); tap("personnel.archive.confirm")
            wait("personnel.archived"); return
            }
            check(phase=="restore")
            tap("personnel.archived"); find(); tap("personnel.restore"); tap("personnel.save"); wait("personnel.edit"); tap("personnel.back")
            for(action in listOf("write_off","paid_off")) {
                tap("qa.$action"); state("$action|idle|readonly"); node("personnel.add").assertIsNotEnabled()
                tap("qa.reset"); state("reset|idle|write")
            }
            tap("qa.write_off"); state("write_off|idle|readonly")
            tap("qa.read_off"); state("read_off|idle|readonly"); node("personnel.add").assertDoesNotExist()
            tap("qa.reset"); state("reset|idle|write")
            tap("qa.company.b"); wait("qa.no.scope")
            tap("qa.account.b"); state("account.b|idle"); tap("qa.company.a"); wait("qa.no.scope")
            tap("qa.company.b"); wait("personnel.add"); compose.onNodeWithText("Native android Son").assertDoesNotExist()
            tap("qa.account.a"); state("account.a|idle"); tap("qa.company.a"); wait("personnel.add"); find(); wait("personnel.edit")
        }
    }
}
