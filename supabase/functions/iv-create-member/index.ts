import {serve} from '../_shared/runtime.ts';
import {provision} from '../_shared/provision.ts';
serve((req,input)=>provision(req,input,'member'));
