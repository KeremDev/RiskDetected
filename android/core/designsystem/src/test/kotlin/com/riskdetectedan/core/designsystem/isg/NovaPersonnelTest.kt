package com.riskdetectedan.core.designsystem.isg

import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class NovaPersonnelTest {
    private val scope = NovaPersonnelScope(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "first")
    private val row = NovaEmployeeRow(UUID.randomUUID(), scope.ownerID, scope.companyID, "Ada", null, null, 5, false)
    @Test fun nameOnlyAndNoDoubleSubmit() {
        assertNull(NovaEmployeeEditorState().begin(scope,null).pending)
        val state=NovaEmployeeEditorState(name="Ada Kaya").begin(scope,null)
        assertEquals(NovaEmployeeDepartment.None,state.pending!!.department)
        assertEquals(0L,state.pending.expectedVersion);assertNull(state.pending.employeeID)
        assertNotEquals(state.pending.operationID,state.pending.mutationID)
        assertEquals(state,state.begin(scope,null));assertFalse(state.canEdit)
    }
    @Test fun unknownResultRetainsExactIntentOnlyForSameScope() {
        val start=NovaEmployeeEditorState(name="Ada").begin(scope,null);val intent=start.pending!!
        val unknown=start.uncertain(intent,scope)
        assertEquals(unknown,unknown.retry(scope.copy(sessionID=UUID.randomUUID())))
        assertEquals(intent,unknown.retry(scope).pending)
        val commit=NovaEmployeeCommit(intent.operationID,UUID.randomUUID(),scope.ownerID,scope.companyID,0,false)
        assertEquals(NovaEmployeeEditorState.Phase.committed,unknown.retry(scope).complete(intent,commit,scope).phase)
    }
    @Test fun foreignRowsDepartmentsAndArchiveCreateRejected() {
        val state=NovaEmployeeEditorState(name="Ada")
        assertNull(state.begin(scope,row.copy(companyID=UUID.randomUUID())).pending)
        assertNull(state.begin(scope,row.copy(isArchived=true)).pending)
        assertNull(state.begin(scope,null,true).pending)
        assertNull(state.copy(selectedDepartment=NovaDepartmentRow(UUID.randomUUID(),UUID.randomUUID(),scope.companyID,"Foreign")).begin(scope,null).pending)
    }
    @Test fun keepClearAndNewAreDifferentIntents() {
        val dep=NovaDepartmentRow(UUID.randomUUID(),scope.ownerID,scope.companyID,"Bakım")
        val original=row.copy(departmentID=dep.id,departmentName=dep.name)
        assertEquals(NovaEmployeeDepartment.Keep,NovaEmployeeEditorState(name="Ada",selectedDepartment=dep).begin(scope,original).pending!!.department)
        assertEquals(NovaEmployeeDepartment.None,NovaEmployeeEditorState(name="Ada").begin(scope,original).pending!!.department)
        assertEquals(NovaEmployeeDepartment.New("Yeni"),NovaEmployeeEditorState(name="Ada",departmentText=" Yeni ").begin(scope,null).pending!!.department)
    }
    @Test fun versionAndArchiveMetadataMustMatchAndConflictLocksEditor() {
        val state=NovaEmployeeEditorState(name="Ada").begin(scope,row,true);val intent=state.pending!!
        val wrong=NovaEmployeeCommit(intent.operationID,row.id,scope.ownerID,scope.companyID,5,true)
        assertEquals(NovaEmployeeEditorState.Phase.uncertain,state.complete(intent,wrong,scope).phase)
        assertEquals(NovaEmployeeEditorState.Phase.committed,state.complete(intent,wrong.copy(version=6),scope).phase)
        val rejected=state.reject(intent,scope,true)
        assertNull(rejected.pending);assertFalse(rejected.canEdit)
    }
}
