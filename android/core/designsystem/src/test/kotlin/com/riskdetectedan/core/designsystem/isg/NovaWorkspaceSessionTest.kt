package com.riskdetectedan.core.designsystem.isg

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class NovaWorkspaceSessionTest {
    @Test fun switchInvalidatesOldEpochAndRevision() {
        val user=UUID.randomUUID(); val actor=NovaSessionIdentity(user,UUID.randomUUID())
        val first=NovaWorkspaceSelection(UUID.randomUUID(),UUID.randomUUID(),user,"personal",0,0,true,true)
        val second=NovaWorkspaceSelection(UUID.randomUUID(),UUID.randomUUID(),user,"osgb",4,2,true,true)
        var host=NovaSessionHost(setOf(NovaDestination.companies,NovaDestination.findings)).adopt(actor)
        host=host.beginWorkspaceSwitch(first); val firstTicket=assertNotNull(host.pending).let{host.pending!!}
        host=host.resolve(firstTicket,user,setOf(NovaDestination.companies)); val oldEpoch=host.navigation.epoch
        val old=host.scope("personal",oldEpoch); val stale=host.beginAvailabilityRefresh().pending!!
        host=host.beginWorkspaceSwitch(second); val current=host.pending!!
        assertNotEquals(oldEpoch,host.navigation.epoch); assertNull(host.value(old))
        assertSame(host,host.resolve(stale,user,setOf(NovaDestination.companies)))
        host=host.resolve(current,user,setOf(NovaDestination.companies,NovaDestination.findings))
        assertTrue(host.isCurrent(host.navigation.epoch,second.workspaceID,4))
        assertFalse(host.isCurrent(host.navigation.epoch,first.workspaceID,0))
    }

    @Test fun foreignUserWorkspaceIsRejectedWithoutEpochChurn() {
        val actor=NovaSessionIdentity(UUID.randomUUID(),UUID.randomUUID())
        val host=NovaSessionHost(setOf(NovaDestination.companies)).adopt(actor)
        val foreign=NovaWorkspaceSelection(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID(),"osgb",0,0,true,true)
        assertSame(host,host.beginWorkspaceSwitch(foreign))
    }
}
