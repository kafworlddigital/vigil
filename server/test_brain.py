import unittest,tempfile,time,json,io,urllib.error
from unittest.mock import patch
from pathlib import Path
from vigil_brain import BrainRouter,Failure,DeviceRegistry,digest,enrol_device

def candidate(provider,model,vision=True):
 hosts={'opencode-go':'opencode.ai','openrouter':'openrouter.ai','nvidia':'integrate.api.nvidia.com'}
 return dict(provider=provider,model=model,vision=vision,endpoint='https://'+hosts[provider]+'/v1/chat/completions',protocol='chat')

class BrainTests(unittest.TestCase):
 def setUp(self):
  self.models=[candidate('opencode-go','a'),candidate('openrouter','b:free'),candidate('nvidia','c')]
  self.keys={m['provider']:'synthetic' for m in self.models}
 def test_go_request_matches_opencode_and_keeps_credentials_out_of_url(self):
  m=candidate('opencode-go','glm-5.3-flash',False)
  m['endpoint']='https://opencode.ai/inference/go/openai/v1/chat/completions'
  router=BrainRouter([m],{'opencode-go':'synthetic-go','_opencode-go-org-id':'synthetic-org'})
  with patch('vigil_brain.urllib.request.urlopen') as send:
   send.return_value.__enter__.return_value=io.StringIO(json.dumps({'choices':[{'message':{'content':'ok'}}]}))
   self.assertEqual(router.http(m,{'text':'synthetic'},5),'ok')
   req=send.call_args.args[0];headers={k.lower():v for k,v in req.header_items()}
   self.assertEqual(req.full_url,m['endpoint'])
   self.assertEqual(headers['authorization'],'Bearer synthetic-go')
   self.assertTrue(headers['user-agent'].startswith('opencode/'))
   self.assertEqual(headers['x-opencode-org-id'],'synthetic-org')
   self.assertEqual(headers['x-opencode-session'],headers['x-opencode-session-id'])
   self.assertEqual(headers['x-opencode-client'],'cli')
   self.assertTrue(headers['x-opencode-request'].startswith('msg_'))
 def test_forbidden_response_does_not_claim_key_is_invalid(self):
  router=BrainRouter(self.models,self.keys)
  error=urllib.error.HTTPError(self.models[0]['endpoint'],403,'Forbidden',{},io.BytesIO(b'Cloudflare blocked request'))
  with patch('vigil_brain.urllib.request.urlopen',side_effect=error):
   with self.assertRaises(Failure) as caught:router.http(self.models[0],{'text':'synthetic'},5)
   self.assertEqual(caught.exception.kind,'forbidden')
 def test_first_two_fail_third_answers(self):
  calls=[]
  def transport(m,prompt,timeout,probe=False):
   calls.append(m['provider']);self.assertLessEqual(timeout,20)
   if m['provider'] in ['opencode-go','openrouter']:raise Failure('429',time.time()+60)
   return 'Third provider answered'
  router=BrainRouter(self.models,self.keys,transport)
  for i,m in enumerate(self.models):router.health[router.id(m)].update(status='green',latency=i)
  reply=router.complete({'text':'synthetic'})
  self.assertEqual(reply['provider'],'nvidia');self.assertFalse(reply['local'])
  self.assertEqual(calls,['opencode-go','openrouter','nvidia'])
  self.assertEqual(sum(s['status']=='amber' for s in router.snapshot()),2)
 def test_screen_vision_gate_and_local_json(self):
  calls=[]
  def fail(m,*args):calls.append(m);raise Failure('unavailable',time.time()+60)
  text=candidate('nvidia','text',False)
  router=BrainRouter([text]+self.models,self.keys,fail)
  reply=router.complete({'text':'Task: Unknown\nApp: Unclear','image':'synthetic'})
  self.assertTrue(reply['local']);self.assertTrue(all(m['vision'] for m in calls))
  self.assertEqual(json.loads(reply['text'])['choice'],'uncertain')
 def test_cooldown_persisted_and_expires(self):
  calls=[]
  def transport(m,*args):calls.append(m);raise Failure('429',time.time()+60)
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'health.json';router=BrainRouter(self.models[:1],self.keys,transport,path)
   router.probe_all();self.assertEqual(len(calls),1)
   again=BrainRouter(self.models[:1],self.keys,transport,path)
   again.probe_all();self.assertEqual(len(calls),1)
   again.probe_all(time.time()+61);self.assertEqual(len(calls),2)
 def test_forbidden_models(self):
  for name in ['openai/test','gpt-6','vendor/GPT-something','codex-model']:
   self.assertFalse(BrainRouter.permitted(candidate('openrouter',name)))
 def test_single_use_activation_and_token_hash_only(self):
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'devices.json';registry=DeviceRegistry(path)
   registry.state['codes'][digest('synthetic-code')]={'edition':'macy','expires':time.time()+60}
   self.assertIsNone(registry.activate('synthetic-code','keith','device'))
   token=registry.activate('synthetic-code','macy','device');self.assertIsNotNone(token)
   self.assertEqual(registry.valid(token)['edition'],'macy')
   self.assertIsNone(registry.activate('synthetic-code','macy','device'))
   self.assertNotIn(token,path.read_text())
 def test_unsigned_enrolment_rejected(self):
  with tempfile.TemporaryDirectory() as folder:
   registry=DeviceRegistry(Path(folder)/'devices.json')
   with self.assertRaises(Exception):enrol_device(registry,{'bundle':'com.evil.app','device':'synthetic-device-value','transaction':'unsigned'})

if __name__=='__main__':unittest.main()
