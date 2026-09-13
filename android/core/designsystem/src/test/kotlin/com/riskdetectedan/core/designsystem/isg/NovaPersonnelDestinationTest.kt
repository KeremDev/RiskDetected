package com.riskdetectedan.core.designsystem.isg

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[33])
class NovaPersonnelDestinationTest {
    @get:Rule val compose=createComposeRule()
    private val scope=NovaPersonnelScope(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID(),"first")
    private val employeeID=UUID.randomUUID()
    private var saved: NovaEmployeeRow?=null
    private val intents=mutableListOf<NovaEmployeeIntent>()
    private fun client(failFirst:Boolean=false)=NovaPersonnelClient(
        employees={_,_,archived,_->NovaEmployeePage(listOfNotNull(saved).filter { archived || !it.isArchived },null)},
        departments={_,_,_->NovaDepartmentPage(emptyList(),null)},detail={_,_->requireNotNull(saved)},
        save={ intent ->
            intents.add(intent)
            if(failFirst && intents.size==1) throw NovaPersonnelFailure(NovaPersonnelFailure.Kind.unavailable)
            val depName=(intent.department as? NovaEmployeeDepartment.New)?.name
            saved=NovaEmployeeRow(employeeID,scope.ownerID,scope.companyID,intent.name,
                depName?.let{UUID.randomUUID()},depName,if(intent.action==NovaEmployeeIntent.Action.create)0 else intent.expectedVersion+1,intent.action==NovaEmployeeIntent.Action.archive)
            NovaEmployeeCommit(intent.operationID,employeeID,scope.ownerID,scope.companyID,saved!!.version,saved!!.isArchived)
        })
    private fun start(client:NovaPersonnelClient=client()) {
        compose.setContent { NovaTheme(false) { NovaPersonnelDestination(scope,"Sentetik firma",client,{}) } }
        compose.mainClock.advanceTimeBy(250);compose.waitForIdle()
    }
    private fun add() {
        compose.onNodeWithTag("personnel.add").performScrollTo().performClick()
        compose.onNodeWithTag("personnel.name").performTextInput("Ada Kaya")
    }
    @Test fun nameAloneCreatesAndOpensDetailWithoutDateFields() {
        start();add()
        compose.onNodeWithText("Başlangıç tarihi").assertDoesNotExist()
        compose.onNodeWithText("Bitiş tarihi").assertDoesNotExist()
        compose.onNodeWithTag("personnel.save").performScrollTo().performClick()
        compose.onNodeWithTag("personnel.detail").assertIsDisplayed()
        compose.onNodeWithText("Ada Kaya").assertIsDisplayed()
        compose.runOnIdle { assertEquals(NovaEmployeeDepartment.None,intents.single().department) }
    }
    @Test fun inlineDepartmentIsPassedWithEmployeeNotSeparatelySaved() {
        start();add()
        compose.onNodeWithTag("personnel.department").performTextInput("Bakım")
        compose.onNodeWithTag("personnel.save").performScrollTo().performClick()
        compose.onNodeWithText("Bakım").assertIsDisplayed()
        compose.runOnIdle { assertEquals(NovaEmployeeDepartment.New("Bakım"),intents.single().department) }
    }
    @Test fun uncertainResultCannotLeaveAndRetriesSameMutationKey() {
        start(client(true));add()
        compose.onNodeWithTag("personnel.save").performScrollTo().performClick()
        compose.onNodeWithTag("personnel.back").assertIsNotEnabled()
        compose.onNodeWithTag("personnel.retry").performScrollTo().performClick()
        compose.onNodeWithTag("personnel.detail").assertIsDisplayed()
        compose.runOnIdle { assertEquals(2,intents.size);assertEquals(intents[0],intents[1]) }
    }
    @Test fun archiveRequiresCommonPopupConfirmationAndKeepsHistoryRow() {
        saved=NovaEmployeeRow(employeeID,scope.ownerID,scope.companyID,"Ada Kaya",null,null,0,false)
        start()
        compose.onNodeWithTag("personnel.row.$employeeID").performScrollTo().performClick()
        compose.onNodeWithTag("personnel.edit").performClick()
        compose.onNodeWithTag("personnel.archive").performScrollTo().performClick()
        compose.onNodeWithTag("nova.panel.scroll").assertIsDisplayed()
        compose.onNodeWithTag("personnel.archive.cancel").performClick()
        compose.runOnIdle { assertTrue(intents.isEmpty()) }
        compose.onNodeWithTag("personnel.archive").performClick()
        compose.onNodeWithTag("personnel.archive.confirm").performClick()
        compose.runOnIdle { assertTrue(saved!!.isArchived);assertEquals(1L,saved!!.version) }
    }
    @Test fun lateResponseFromPreviousScopeIsNeverShown() {
        var current by mutableStateOf(scope)
        val delayed=CompletableDeferred<NovaEmployeePage>()
        var replacementLoaded=false
        val other=scope.copy(ownerID=UUID.randomUUID(),sessionID=UUID.randomUUID(),epoch="next")
        val client=NovaPersonnelClient(employees={s,_,_,_->if(s==scope)withContext(NonCancellable){delayed.await()} else { replacementLoaded=true; NovaEmployeePage(emptyList(),null) }},departments={_,_,_->NovaDepartmentPage(emptyList(),null)},detail={_,_->error("unused")},save={error("unused")})
        compose.setContent { NovaTheme(false){NovaPersonnelDestination(current,"Test",client,{})} }
        compose.mainClock.advanceTimeBy(250);compose.waitForIdle()
        compose.runOnIdle { current=other }
        compose.mainClock.advanceTimeBy(250);compose.waitForIdle()
        compose.runOnIdle { delayed.complete(NovaEmployeePage(listOf(NovaEmployeeRow(employeeID,scope.ownerID,scope.companyID,"Eski hesap",null,null,0,false)),null)) }
        compose.mainClock.advanceTimeBy(500)
        compose.waitUntil(3000) { replacementLoaded }
        compose.waitForIdle()
        compose.onNodeWithText("Eski hesap").assertDoesNotExist()
        compose.onNodeWithTag("personnel.list").performScrollToNode(hasText("Henüz personel yok."))
        compose.onNodeWithText("Henüz personel yok.").assertExists()
    }
}
