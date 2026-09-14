import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
function run(cmd,args){const r=spawnSync(cmd,args,{encoding:'utf8',maxBuffer:8e6});if(r.status!==0)throw new Error(r.stderr||r.stdout);return r.stdout.trim();}
const sdk=run('xcrun',['--sdk','iphonesimulator','--show-sdk-path']);
run('xcrun',['swiftc','-sdk',sdk,'-target','arm64-apple-ios16.0-simulator','-D','EDUCATION_RENDER_TEST','-parse-as-library',
 root+'App/Services/Company/NovaEducationModels.swift',root+'App/DesignSystem/ISG/NovaEducationCertificatePDF.swift',root+'scripts/education/RenderChecks.swift','-o','/tmp/nova-education-render-checks']);
const devices=JSON.parse(run('xcrun',['simctl','list','devices','booted','--json']));
const simulator=process.env.EDUCATION_SIMULATOR_ID||Object.values(devices.devices).flat().find(d=>d.state==='Booted' && d.isAvailable)?.udid;
if(!simulator)throw new Error('Boot an iOS simulator or set EDUCATION_SIMULATOR_ID');
console.log(run('xcrun',['simctl','spawn',simulator,'/tmp/nova-education-render-checks',root]));
