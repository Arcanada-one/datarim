#!/usr/bin/env python3
"""Structural validation for product-artifact/1 Markdown bundles."""
import argparse, hashlib, json, os, re, sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"check-product-artifact: PyYAML unavailable: {exc}", file=sys.stderr)
    raise SystemExit(2)

class UniqueLoader(yaml.SafeLoader):
    pass

def construct_mapping(loader, node, deep=False):
    out = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in out:
            raise ValueError(f"duplicate key: {key}")
        out[key] = loader.construct_object(value_node, deep=deep)
    return out
UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping)

TYPES = {
 'opportunity-brief': {'question','segment','actors','context','claims','current_workaround','problem_cost','alternatives','distribution_assumptions','constraints','unknowns','next_discriminating_action','source_refs','provenance'},
 'source-evidence-ledger': {'entries','search_scope','search_completed_at','source_refs','provenance'},
 'hypothesis-card': {'scope','segment','prediction','alternative_explanation','disconfirming_observation','assumptions','measurement_unit','applicability_criteria','protocol_ref','evidence_refs','source_refs','provenance'},
 'experiment-protocol': {'hypothesis_ref','method','sampling_rule','analysis_unit','randomization_unit','randomization_not_applicable_reason','primary_outcome','secondary_outcomes','sample_rule','threshold_decision_map','exclusion_rule','missing_data_rule','stop_rule','duration_cap','budget_cap','grant_ref','privacy_disclosure','observation_format','analysis_code_pin','source_refs','provenance'},
 'decision-record': {'question','options','selected_option','business_outcome','evidence_refs','counterevidence_refs','applicable_thresholds','uncertainty','reversal_conditions','owner','approved_scope_delta','strategist_recommendation','evidence_acceptance','authority_to_act','scope_delta','source_refs','provenance'},
 'product-brief': {'accepted_intent','requirements','risk','scope','non_goals','hypothesis_refs','input_revisions','success_criteria','acceptance_owner','downstream_task_ref','source_refs','provenance'},
}
FRONT={'schema_version','id','artifact_type','revision','status','acceptance_state','source_digest','supersedes'}
COMMON={'source_refs','provenance'}
REQUIRED = {
 'opportunity-brief': {'question','segment','actors','context','claims','current_workaround','problem_cost','alternatives','distribution_assumptions','constraints','unknowns','next_discriminating_action'},
 'source-evidence-ledger': {'entries','search_scope','search_completed_at'},
 'hypothesis-card': {'scope','segment','prediction','alternative_explanation','disconfirming_observation','assumptions','measurement_unit','applicability_criteria','protocol_ref','evidence_refs'},
 'experiment-protocol': {'hypothesis_ref','method','sampling_rule','analysis_unit','randomization_unit','randomization_not_applicable_reason','primary_outcome','secondary_outcomes','sample_rule','threshold_decision_map','exclusion_rule','missing_data_rule','stop_rule','duration_cap','budget_cap','grant_ref','privacy_disclosure','observation_format','analysis_code_pin'},
 'decision-record': {'question','options','selected_option','business_outcome','evidence_refs','counterevidence_refs','applicable_thresholds','uncertainty','reversal_conditions','owner','approved_scope_delta'},
 'product-brief': {'accepted_intent','requirements','risk','scope','non_goals','hypothesis_refs','input_revisions','success_criteria','acceptance_owner','downstream_task_ref'},
}
DECISION_V2_REQUIRED = {
 'question','options','selected_option','business_outcome','strategist_recommendation',
 'evidence_acceptance','authority_to_act','evidence_refs','counterevidence_refs',
 'applicable_thresholds','uncertainty','reversal_conditions','owner','scope_delta',
}
DECISION_V2_FIELDS = {'strategist_recommendation','evidence_acceptance','authority_to_act','scope_delta'}
REF=re.compile(r'^sha256:[0-9a-f]{64}$')
TS=re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$')
MIN_STATUS={'opportunity-brief':'ready_for_research','source-evidence-ledger':'recorded','hypothesis-card':'test_ready','experiment-protocol':'protocol_frozen','decision-record':'submitted','product-brief':'ready_for_delivery'}
KC_TERM=re.compile(r'(?i)\bknowledge[\s-]+contract\b')
KC_NEGATION_TAIL=re.compile(r"(?i)(?:\b(?:not|never)\s+(?:(?:a|an|the|any|official|legal|valid)\s+){0,3}|\bno\s+|\b(?:isn't|aren't|wasn't|weren't|doesn't|don't|didn't|won't|can't)\s+(?:(?:a|an|the|any|official|legal|valid)\s+){0,3})$")

def has_affirmative_kc_label(text):
 # KC terms are refused unless their immediate clause explicitly negates them.
 # Clause boundaries prevent a nearby disclaimer from excusing a later claim.
 for match in KC_TERM.finditer(text):
  start=max(text.rfind(mark,0,match.start()) for mark in ('\n','.',';','!','?',':'))+1
  if not KC_NEGATION_TAIL.search(text[start:match.start()]): return True
 return False

class Checker:
 def __init__(self, root): self.root=root.resolve(); self.diags=[]; self.docs=[]; self.byid={}; self.sources=[]
 def add(self,path,code): self.diags.append((str(path),code))
 def safe_yaml(self,text,path):
  loader=None
  try:
   loader=UniqueLoader(text)
   value=loader.get_single_data()
   if not isinstance(value,dict): raise ValueError('mapping required')
   return value
  except Exception as exc:
   self.add(path,'E_YAML_INVALID'); return None
  finally:
   if loader is not None: loader.dispose()
 def parse(self,path):
  rel=path.relative_to(self.root).as_posix()
  try: raw=path.read_bytes()
  except OSError: self.add(rel,'E_FILE_READ'); return
  if b'\r' in raw or not raw.endswith(b'\n'):
   self.add(rel,'E_TEXT_FORMAT')
  try: text=raw.decode('utf-8')
  except UnicodeDecodeError: self.add(rel,'E_TEXT_FORMAT'); return
  if len(re.findall(r'(?m)^---\s*$',text))!=2: self.add(rel,'E_FRONTMATTER')
  if text.count('```product-artifact-data') != 1:
   self.add(rel,'E_DATA_FENCE'); return
  m=re.match(r'^---\n(.*?)\n---\n',text,re.S)
  if not m: self.add(rel,'E_FRONTMATTER'); return
  fm=self.safe_yaml(m.group(1),rel)
  dm=re.search(r'```product-artifact-data\n(.*?)\n```\n?',text,re.S)
  if not dm: self.add(rel,'E_DATA_FENCE'); return
  data=self.safe_yaml(dm.group(1),rel)
  if fm is None or data is None: return
  doc={'path':rel,'bytes':raw,'front':fm,'data':data}
  # Refuse affirmative self-labels; allow explicit negation in this clause.
  if has_affirmative_kc_label(text): self.add(rel,'E_KC_SELF_LABEL')
  self.docs.append(doc)
  aid=fm.get('id'); rev=fm.get('revision')
  if isinstance(aid,str):
   key=(aid,rev)
   if key in self.byid: self.add(rel,'E_ID_DUPLICATE')
   else: self.byid[key]=doc
  self.sources.extend((entry,doc) for entry in data.get('entries',[]) if isinstance(entry,dict))
 def unknown(self,mapping,allowed,path):
  if isinstance(mapping,dict):
   for key in mapping:
    if key not in allowed:
     self.add(path,'E_KC_SELF_LABEL' if key in {'kc_contract','contract_authority','knowledge_contract'} else 'E_KEY_UNKNOWN')
 def validate_doc(self,doc):
  p=doc['path']; f=doc['front']; d=doc['data']; typ=f.get('artifact_type')
  self.unknown(f,FRONT,p)
  if set(f)-FRONT: pass
  if not FRONT.issubset(f): self.add(p,'E_FIELD_REQUIRED')
  schema=f.get('schema_version')
  if schema not in {'product-artifact/1','product-artifact/2'} or (schema=='product-artifact/2' and typ!='decision-record'): self.add(p,'E_SCHEMA_VERSION')
  if not isinstance(f.get('id'),str) or not f.get('id','').startswith('artifact:') or not f.get('id','')[9:]: self.add(p,'E_ID_INVALID')
  if type(f.get('revision')) is not int or f.get('revision',0)<1: self.add(p,'E_REVISION_INVALID')
  if typ not in TYPES: self.add(p,'E_TYPE_INVALID'); return
  self.unknown(d,TYPES[typ],p)
  required=DECISION_V2_REQUIRED if schema=='product-artifact/2' and typ=='decision-record' else REQUIRED[typ]
  if not (COMMON|required).issubset(d): self.add(p,'E_FIELD_REQUIRED')
  if schema=='product-artifact/1' and typ=='decision-record' and set(d).intersection(DECISION_V2_FIELDS): self.add(p,'E_SCHEMA_VERSION')
  if schema=='product-artifact/2' and typ=='decision-record' and 'approved_scope_delta' in d: self.add(p,'E_SCHEMA_VERSION')
  if typ=='opportunity-brief' and isinstance(d.get('claims'),list):
   for claim in d['claims']: self.unknown(claim,{'id','claim_type','statement','scope','kind','supporting_refs','contradicting_refs','provenance_ref','method','input_refs','code_ref','rationale','unknown_reason','availability'},p)
  if typ=='source-evidence-ledger' and isinstance(d.get('entries'),list) and not d['entries']:
   if not (d.get('search_scope') and d.get('search_completed_at') and d.get('provenance',{}).get('search_method')): self.add(p,'E_LEDGER_EMPTY_SEARCH')
  statuses={'opportunity-brief':{'draft','ready_for_research','superseded'},'source-evidence-ledger':{'draft','recorded','superseded'},'hypothesis-card':{'draft','test_ready','under_test','supported','refuted','inconclusive'},'experiment-protocol':{'draft','protocol_frozen'},'decision-record':{'draft','submitted','superseded'},'product-brief':{'draft','ready_for_delivery','superseded'}}
  if f.get('status') not in statuses[typ]: self.add(p,'E_STATUS_INVALID')
  if f.get('acceptance_state') not in {'not_submitted','submitted','accepted','needs_evidence','rejected'}: self.add(p,'E_ACCEPTANCE_INVALID')
  if not isinstance(d.get('provenance'),dict) or not {'recorder','recorded_at','origin_kind'}.issubset(d.get('provenance',{})): self.add(p,'E_PROVENANCE_INVALID')
  elif not TS.fullmatch(str(d['provenance'].get('recorded_at',''))): self.add(p,'E_TIMESTAMP_INVALID')
  if f.get('source_digest') is not None and not REF.fullmatch(str(f.get('source_digest'))): self.add(p,'E_SOURCE_DIGEST_INVALID')
  refs=d.get('source_refs',[])
  if not isinstance(refs,list): self.add(p,'E_REF_INVALID'); refs=[]
  canonical=[]
  for r in refs:
   if not isinstance(r,dict) or set(r)!={'id','revision','digest'} or type(r.get('revision')) is not int or r.get('revision',0)<1 or not isinstance(r.get('id'),str) or not REF.fullmatch(str(r.get('digest',''))): self.add(p,'E_REF_INVALID')
   else: canonical.append({k:r[k] for k in ('id','revision','digest')})
  if not refs and f.get('source_digest') is not None: self.add(p,'E_SOURCE_DIGEST_MISMATCH')
  elif refs:
   canonical.sort(key=lambda r:r['id'].encode('utf-8'))
   encoded=json.dumps(canonical,ensure_ascii=False,separators=(',',':')).encode()
   if f.get('source_digest')!='sha256:'+hashlib.sha256(encoded).hexdigest(): self.add(p,'E_SOURCE_DIGEST_MISMATCH')
  self.validate_fields(doc,typ)
 def validate_fields(self,doc,typ):
  p=doc['path']; f=doc['front']; d=doc['data']
  if typ=='opportunity-brief':
   self.unknown(d.get('actors'),{'user','buyer','payer'},p)
   for k in ('question','segment','context','next_discriminating_action'):
    if k=='next_discriminating_action' and d.get(k) is None: continue
    if not isinstance(d.get(k),str) or not d.get(k).strip(): self.add(p,'E_FIELD_REQUIRED')
   if not isinstance(d.get('actors'),dict) or not {'user','buyer','payer'}.issubset(d.get('actors',{})) or any(v is not None and not isinstance(v,str) for v in d.get('actors',{}).values()): self.add(p,'E_ACTORS_INVALID')
   for k in ('current_workaround','problem_cost'):
    if d.get(k) is not None and not isinstance(d.get(k),str): self.add(p,'E_FIELD_TYPE')
   for k in ('alternatives','distribution_assumptions','constraints','unknowns'):
    if not isinstance(d.get(k),list) or any(not isinstance(v,str) for v in d.get(k,[])): self.add(p,'E_FIELD_TYPE')
   for claim in d.get('claims',[]) if isinstance(d.get('claims'),list) else []: self.claim(claim,f,p)
  if typ=='source-evidence-ledger':
   for entry in d.get('entries',[]) if isinstance(d.get('entries'),list) else []:
    self.unknown(entry,{'id','revision','locator','origin_kind','origin_family','duplicate_group','conflict_group','publisher_or_actor','observed_by','observed_at','published_at','published_at_basis_ref','retrieved_at','purpose','raw_ref','availability','search_status','disclosure','unavailable_reason','search_method','media_type'},p)
    if not {'id','revision','locator','origin_kind','publisher_or_actor','observed_by','observed_at','published_at','retrieved_at','purpose','raw_ref','availability','search_status','disclosure','unavailable_reason','search_method','media_type'}.issubset(entry): self.add(p,'E_SOURCE_ENTRY_INVALID')
    if not isinstance(entry.get('id'),str) or not entry.get('id','').startswith('source:') or type(entry.get('revision')) is not int or entry.get('revision',0)<1: self.add(p,'E_SOURCE_ENTRY_INVALID')
    if 'origin_family' in entry and (not isinstance(entry.get('origin_family'),str) or not entry.get('origin_family','').strip()): self.add(p,'E_SOURCE_FAMILY_INVALID')
    for group_key in ('duplicate_group','conflict_group'):
     if entry.get(group_key) is not None and (not isinstance(entry.get(group_key),str) or not entry[group_key].strip()): self.add(p,'E_SOURCE_GROUP_INVALID')
    if entry.get('raw_ref') is not None:
     if not isinstance(entry['raw_ref'],dict) or set(entry['raw_ref'])!={'id','revision','digest'} or not str(entry['raw_ref'].get('id','')).startswith('raw:'): self.add(p,'E_REF_INVALID')
     else: self.resolve_raw(entry['raw_ref'],p)
    for k in ('observed_at','published_at','retrieved_at'):
     if entry.get(k) is not None and not TS.fullmatch(str(entry[k])): self.add(p,'E_TIMESTAMP_INVALID')
    if entry.get('availability')=='unavailable' and (not entry.get('locator') or not entry.get('unavailable_reason') or not entry.get('search_method') or entry.get('search_status')!='incomplete' or entry.get('raw_ref') is not None): self.add(p,'E_SOURCE_UNAVAILABLE_INVALID')
    if entry.get('availability')=='available' and entry.get('search_status')=='incomplete' and entry.get('raw_ref') is None: self.add(p,'E_SOURCE_UNAVAILABLE_INVALID')
    if entry.get('search_status')=='no_match' and (not d.get('search_scope') or not d.get('search_completed_at') or not entry.get('search_method')): self.add(p,'E_NO_MATCH_INCOMPLETE')
    if entry.get('availability') not in {'available','unavailable'} or entry.get('search_status') not in {'not_searched','match_found','no_match','incomplete'}: self.add(p,'E_SOURCE_ENTRY_INVALID')
    if entry.get('availability')=='available' and not entry.get('locator'): self.add(p,'E_SOURCE_ENTRY_INVALID')
    if entry.get('raw_ref') is None and entry.get('search_status') not in {'no_match','incomplete'} and entry.get('availability')!='unavailable': self.add(p,'E_SOURCE_ENTRY_INVALID')
    if entry.get('published_at') is None:
     if entry.get('published_at_basis_ref') is not None: self.add(p,'E_PUBLISHED_AT_BASIS_INVALID')
    elif entry.get('published_at_basis_ref') != entry.get('raw_ref') or entry.get('raw_ref') is None:
     # A non-null publication date is structurally supported only when it is
     # pinned to this source's raw bytes. This does not assess what those bytes say.
     self.add(p,'E_PUBLISHED_AT_BASIS_INVALID')
    elif not isinstance(entry.get('published_at_basis_ref'),dict): self.add(p,'E_PUBLISHED_AT_BASIS_INVALID')
    elif not self.resolve_raw(entry.get('published_at_basis_ref'),p): self.add(p,'E_PUBLISHED_AT_BASIS_INVALID')
   if d.get('search_completed_at') is not None and not TS.fullmatch(str(d.get('search_completed_at'))): self.add(p,'E_TIMESTAMP_INVALID')
  if typ=='decision-record':
   opts=d.get('options',[])
   for option in opts if isinstance(opts,list) else []:
    if not isinstance(option,dict): self.add(p,'E_OPTION_INVALID'); continue
    self.unknown(option,{'id','description','disposition','rationale'},p)
   if d.get('business_outcome') not in {'continue','pivot','stop','more-evidence'}: self.add(p,'E_OUTCOME_INVALID')
   chosen=[o.get('id') for o in opts if isinstance(o,dict) and o.get('disposition')=='selected']
   if d.get('business_outcome')=='more-evidence' and d.get('selected_option') is None: pass
   elif len(chosen)!=1 or chosen[0]!=d.get('selected_option'): self.add(p,'E_OPTION_SELECTION')
   for option in opts if isinstance(opts,list) else []:
    if not isinstance(option,dict) or option.get('disposition') not in {'selected','rejected','deferred'} or not {'id','description','disposition','rationale'}.issubset(option): self.add(p,'E_OPTION_INVALID')
    elif any(not isinstance(option.get(key),str) or not option[key].strip() for key in ('id','description','rationale')): self.add(p,'E_OPTION_INVALID')
   if f.get('schema_version')=='product-artifact/2':
    if not isinstance(opts,list) or not opts: self.add(p,'E_OPTION_REQUIRED')
    else:
     option_ids=[o.get('id') for o in opts if isinstance(o,dict)]
     if len(option_ids)!=len(opts) or any(not isinstance(i,str) or not i.strip() for i in option_ids) or len(set(option_ids))!=len(option_ids): self.add(p,'E_OPTION_INVALID')
     if not any(isinstance(o,dict) and o.get('disposition') in {'rejected','deferred'} for o in opts): self.add(p,'E_OPTION_DISPOSITION_REQUIRED')
    for key in ('evidence_refs','counterevidence_refs','applicable_thresholds','uncertainty','reversal_conditions'):
     if not isinstance(d.get(key),list): self.add(p,'E_FIELD_TYPE')
     elif key in {'uncertainty','reversal_conditions'} and (not d[key] or any(not isinstance(item,str) or not item.strip() for item in d[key])): self.add(p,'E_FIELD_REQUIRED')
    for key in ('question','owner'):
     if not isinstance(d.get(key),str) or not d[key].strip(): self.add(p,'E_FIELD_REQUIRED')
    if d.get('strategist_recommendation') not in {'GO','NO_GO','PIVOT','INCOMPLETE','NOT_APPLICABLE'}: self.add(p,'E_RECOMMENDATION_INVALID')
    if d.get('evidence_acceptance') not in {'pending','accepted','rejected','insufficient'}: self.add(p,'E_EVIDENCE_ACCEPTANCE_INVALID')
    authority=d.get('authority_to_act')
    if not isinstance(authority,dict) or set(authority)!={'status','authority_ref'} or authority.get('status') not in {'none','granted'}: self.add(p,'E_AUTHORITY_INVALID')
    elif authority.get('status')=='granted' and (not isinstance(authority.get('authority_ref'),str) or not authority.get('authority_ref').strip()): self.add(p,'E_AUTHORITY_REF_REQUIRED')
    elif authority.get('status')=='none' and authority.get('authority_ref') is not None: self.add(p,'E_AUTHORITY_REF_INVALID')
    if not isinstance(d.get('scope_delta'),str) or not d.get('scope_delta','').strip(): self.add(p,'E_SCOPE_DELTA_INVALID')
    if d.get('strategist_recommendation')=='GO' and not d.get('counterevidence_refs'): self.add(p,'E_COUNTEREVIDENCE_REQUIRED')
  if typ=='experiment-protocol':
   budget=d.get('budget_cap')
   if not isinstance(budget,dict) or not {'max_calls','max_cash_cost','budget_ref'}.issubset(budget) or type(budget.get('max_calls')) is not int or budget.get('max_calls',-1)<0 or (budget.get('max_cash_cost') is not None and (type(budget.get('max_cash_cost')) not in (int,float) or budget.get('max_cash_cost')<0)) or not isinstance(budget.get('budget_ref'),str) or not budget.get('budget_ref'): self.add(p,'E_BUDGET_INVALID')
   if d.get('randomization_unit') is None and not d.get('randomization_not_applicable_reason'): self.add(p,'E_RANDOMIZATION_INVALID')
  if typ=='experiment-protocol' and f.get('status')=='protocol_frozen':
   ref=d.get('hypothesis_ref')
   target=self.byid.get((ref.get('id'),ref.get('revision'))) if isinstance(ref,dict) else None
   if not target or target['front'].get('acceptance_state')!='accepted' or target['front'].get('status')!='test_ready': self.add(p,'E_INPUT_NOT_READY')
  self.refs(doc,typ)
 def claim(self,c,f,p):
  if not isinstance(c,dict): self.add(p,'E_CLAIM_INVALID'); return
  allowed={'id','claim_type','statement','scope','kind','supporting_refs','contradicting_refs','provenance_ref','method','input_refs','code_ref','rationale','unknown_reason','availability'}
  self.unknown(c,allowed,p)
  kind=c.get('kind')
  if not {'id','claim_type','statement','scope','kind','supporting_refs','contradicting_refs'}.issubset(c) or kind not in {'observed','derived','assumed','unknown'}: self.add(p,'E_CLAIM_INVALID')
  if not isinstance(c.get('supporting_refs'),list) or not isinstance(c.get('contradicting_refs'),list): self.add(p,'E_CLAIM_INVALID')
  if kind=='observed':
   if not c.get('supporting_refs'): self.add(p,'E_OBSERVED_RAW_REQUIRED')
   if f.get('status')=='draft': self.add(p,'E_DRAFT_OBSERVED_CLAIM')
  elif 'provenance_ref' in c and c.get('provenance_ref') is not None: self.add(p,'E_CLAIM_INVALID')
  if c.get('claim_type')=='observed-customer-evidence' and not c.get('supporting_refs'): self.add(p,'E_OBSERVED_RAW_REQUIRED')
  if kind=='derived' and (not c.get('method') or not c.get('input_refs')): self.add(p,'E_CLAIM_DERIVATION')
  if kind=='assumed' and not c.get('rationale'): self.add(p,'E_CLAIM_RATIONALE')
  if kind=='unknown' and not c.get('unknown_reason'): self.add(p,'E_CLAIM_UNKNOWN_REASON')
  resolved=[]
  for ref in c.get('supporting_refs',[]) if isinstance(c.get('supporting_refs',[]),list) else []:
   entry=self.resolve_raw(ref,p,observed=kind=='observed')
   if entry: resolved.append((ref,entry))
  if kind=='observed':
   matched=self.resolve_raw(c.get('provenance_ref'),p,observed=True)
   if kind=='observed' and resolved and matched and not any(ref==c.get('provenance_ref') and entry is matched for ref,entry in resolved): self.add(p,'E_OBSERVED_PROVENANCE_MISMATCH')
   if matched and matched.get('observed_by') and matched.get('observed_at') and matched.get('origin_kind')=='user_reported': self.add(p,'E_USER_REPORTED_AS_OBSERVED')
   if matched and matched.get('origin_kind') in {'roleplay','simulated','synthetic'}: self.add(p,'E_ROLEPLAY_AS_OBSERVED')
  for key in ('contradicting_refs','input_refs'):
   refs=c.get(key,[])
   if not isinstance(refs,list): self.add(p,'E_REF_INVALID'); continue
   for ref in refs:
    if isinstance(ref,dict) and str(ref.get('id','')).startswith('raw:'): self.resolve_raw(ref,p)
    elif key=='input_refs' and isinstance(ref,dict) and str(ref.get('id','')).startswith('artifact:'):
     target=self.byid.get((ref.get('id'),ref.get('revision')))
     if not target or 'sha256:'+hashlib.sha256(target['bytes']).hexdigest()!=ref.get('digest'): self.add(p,'E_REF_MISSING')
    else: self.add(p,'E_REF_INVALID')
  supporting=c.get('supporting_refs',[]) if isinstance(c.get('supporting_refs',[]),list) else []
  contradicting=c.get('contradicting_refs',[]) if isinstance(c.get('contradicting_refs',[]),list) else []
  if contradicting:
   if any(ref in supporting for ref in contradicting): self.add(p,'E_COUNTEREVIDENCE_DUPLICATE')
   support_groups={entry.get('conflict_group') for ref in supporting if (entry:=self.source_for_raw(ref)) and entry.get('conflict_group')}
   counter_groups={entry.get('conflict_group') for ref in contradicting if (entry:=self.source_for_raw(ref)) and entry.get('conflict_group')}
   if not support_groups.intersection(counter_groups): self.add(p,'E_CONFLICT_LINK')
  # A declared source conflict cannot disappear because a claim omits its
  # contradicting_refs or places both sides among supporting_refs. For every
  # represented conflict group, require exactly one supported member and every
  # other member on the contradicting side.
  for conflict_group in {entry.get('conflict_group') for ref in supporting if (entry:=self.source_for_raw(ref)) and entry.get('conflict_group')}:
   support_refs={json.dumps(ref,sort_keys=True) for ref in supporting if (entry:=self.source_for_raw(ref)) and entry.get('conflict_group')==conflict_group}
   conflict_refs={json.dumps(entry.get('raw_ref'),sort_keys=True) for entry,_ in self.sources if entry.get('conflict_group')==conflict_group}
   counter_refs={json.dumps(ref,sort_keys=True) for ref in contradicting if (entry:=self.source_for_raw(ref)) and entry.get('conflict_group')==conflict_group}
   if len(support_refs)!=1 or counter_refs!=(conflict_refs-support_refs): self.add(p,'E_CONFLICT_COUNTEREVIDENCE_REQUIRED')
 def source_for_raw(self,ref):
  return next((entry for entry,_ in self.sources if entry.get('raw_ref')==ref),None)
 def validate_source_groups(self):
  entries=[(entry,doc) for entry,doc in self.sources]
  families={}
  duplicates={}
  conflicts={}
  for entry,doc in entries:
   family=entry.get('origin_family')
   if isinstance(family,str) and family: families.setdefault(family,[]).append((entry,doc))
   duplicate=entry.get('duplicate_group')
   conflict=entry.get('conflict_group')
   if duplicate: duplicates.setdefault(duplicate,[]).append((entry,doc))
   if conflict: conflicts.setdefault(conflict,[]).append((entry,doc))
  for group in duplicates.values():
   if len(group)<2 or len({item.get('origin_family') for item,_ in group})!=1:
    for _,doc in group: self.add(doc['path'],'E_DUPLICATE_GROUP_INVALID')
  for family,group in families.items():
   if len(group)>1 and (not all(item.get('duplicate_group') for item,_ in group) or len({item.get('duplicate_group') for item,_ in group})!=1):
    for _,doc in group: self.add(doc['path'],'E_DUPLICATE_GROUP_REQUIRED')
  for group in conflicts.values():
   raw_refs=[item.get('raw_ref') for item,_ in group]
   if len(group)<2 or any(ref is None for ref in raw_refs) or len({json.dumps(ref,sort_keys=True) for ref in raw_refs})!=len(raw_refs):
    for _,doc in group: self.add(doc['path'],'E_CONFLICT_GROUP_INVALID')
 def resolve_raw(self,ref,p,observed=False):
  if not isinstance(ref,dict) or set(ref)!={'id','revision','digest'} or type(ref.get('revision')) is not int or not REF.fullmatch(str(ref.get('digest',''))) or not str(ref.get('id','')).startswith('raw:'):
   self.add(p,'E_REF_INVALID'); return None
  found=[e for e,_ in self.sources if e.get('raw_ref')==ref]
  if len(found)!=1:
   self.add(p,'E_REF_MISSING' if observed else 'E_REF_MISSING'); return None
  entry=found[0]
  self.check_locator(entry,ref,p)
  return entry
 def check_locator(self,entry,ref,p):
  loc=entry.get('locator')
  if not isinstance(loc,str): self.add(p,'E_LOCATOR_INVALID'); return
  if not loc.startswith('bundle://'): return
  rel=loc[9:]
  parts=Path(rel).parts
  if not rel or Path(rel).is_absolute() or '..' in parts or any(x in {'.',''} for x in parts): self.add(p,'E_LOCATOR_INVALID'); return
  candidate=self.root/rel
  cur=self.root
  for part in parts:
   cur=cur/part
   if cur.is_symlink(): self.add(p,'E_LOCATOR_INVALID'); return
  if not candidate.is_file(): self.add(p,'E_LOCATOR_INVALID'); return
  digest='sha256:'+hashlib.sha256(candidate.read_bytes()).hexdigest()
  if digest!=ref.get('digest'): self.add(p,'E_REF_DIGEST_MISMATCH')
 def refs(self,doc,typ):
  p=doc['path']; d=doc['data']; f=doc['front']
  for key in ('source_refs','evidence_refs','counterevidence_refs','hypothesis_refs','input_revisions'):
   refs=d.get(key,[])
   if refs is None: continue
   if not isinstance(refs,list): self.add(p,'E_REF_INVALID'); continue
   for ref in refs:
    if not isinstance(ref,dict) or set(ref)!={'id','revision','digest'} or type(ref.get('revision')) is not int or not REF.fullmatch(str(ref.get('digest',''))): self.add(p,'E_REF_INVALID'); continue
    if str(ref.get('id','')).startswith('raw:'): self.resolve_raw(ref,p)
    elif str(ref.get('id','')).startswith('artifact:'):
     target=self.byid.get((ref['id'],ref['revision']))
     if not target or 'sha256:'+hashlib.sha256(target['bytes']).hexdigest()!=ref['digest']: self.add(p,'E_REF_MISSING'); continue
     self.input_guard(doc,target,p)
    else: self.add(p,'E_REF_INVALID')
  # Validate singular refs that can be raw or artifact refs.
  for key in ('protocol_ref','hypothesis_ref','analysis_code_pin','grant_ref'):
   ref=d.get(key)
   if ref is None: continue
   if not isinstance(ref,dict) or set(ref)!={'id','revision','digest'} or type(ref.get('revision')) is not int: self.add(p,'E_REF_INVALID'); continue
   target=self.byid.get((ref['id'],ref['revision'])) if str(ref['id']).startswith('artifact:') else None
   if target:
    if target['front'].get('revision')!=ref['revision']: self.add(p,'E_REF_MISSING')
    else: self.input_guard(doc,target,p)
   elif str(ref['id']).startswith('raw:'): self.resolve_raw(ref,p)
   else: self.add(p,'E_REF_MISSING')
  sup=f.get('supersedes')
  if sup is not None and (not isinstance(sup,dict) or set(sup)!={'id','revision','digest'} or type(sup.get('revision')) is not int): self.add(p,'E_REF_INVALID')
  if isinstance(sup,dict):
   if sup.get('id')!=f.get('id') or type(f.get('revision')) is not int or sup.get('revision')!=f.get('revision')-1 or not REF.fullmatch(str(sup.get('digest',''))): self.add(p,'E_SUPERSEDES_INVALID')
   predecessor=self.byid.get((sup.get('id'),sup.get('revision')))
   if predecessor and ('sha256:'+hashlib.sha256(predecessor['bytes']).hexdigest())!=sup.get('digest'): self.add(p,'E_SUPERSEDES_INVALID')
 def input_guard(self,doc,target,p):
  if doc['front'].get('acceptance_state')!='accepted': return
  if target['front'].get('acceptance_state')!='accepted' or target['front'].get('status')=='draft' or target['front'].get('status')=='superseded': self.add(p,'E_INPUT_NOT_READY')
  if any(x['front'].get('id')==target['front'].get('id') and x['front'].get('revision',0)>target['front'].get('revision',0) for x in self.docs): self.add(p,'E_INPUT_SUPERSEDED')
  t=target['front'].get('artifact_type'); status=target['front'].get('status')
  minimum=MIN_STATUS.get(t)
  if t=='hypothesis-card':
   if status not in {'test_ready','under_test','supported','refuted','inconclusive'}: self.add(p,'E_INPUT_NOT_READY')
  elif status!=minimum: self.add(p,'E_INPUT_NOT_READY')
 def run(self,files,emit_text=True):
  for p in files:self.parse(p)
  for d in list(self.docs):self.validate_doc(d)
  self.validate_source_groups()
  if emit_text:
   for path,code in sorted(set(self.diags),key=lambda x:(x[0].encode(),x[1])): print(f'{path}: {code}')
  return bool(self.diags)

SUMMARY_SCHEMA='DatarimProductArtifactValidationSummary/v1'
SUMMARY_CODES=frozenset('''
E_ACCEPTANCE_INVALID E_ACTORS_INVALID E_AUTHORITY_INVALID E_AUTHORITY_REF_INVALID
E_AUTHORITY_REF_REQUIRED E_BUDGET_INVALID E_CLAIM_DERIVATION E_CLAIM_INVALID
E_CLAIM_RATIONALE E_CLAIM_UNKNOWN_REASON E_CONFLICT_COUNTEREVIDENCE_REQUIRED
E_CONFLICT_GROUP_INVALID E_CONFLICT_LINK E_COUNTEREVIDENCE_DUPLICATE
E_COUNTEREVIDENCE_REQUIRED E_DATA_FENCE E_DRAFT_OBSERVED_CLAIM
E_DUPLICATE_GROUP_INVALID E_DUPLICATE_GROUP_REQUIRED E_EVIDENCE_ACCEPTANCE_INVALID
E_FIELD_REQUIRED E_FIELD_TYPE E_FILE_READ E_FRONTMATTER E_ID_DUPLICATE E_ID_INVALID
E_INPUT_NOT_READY E_INPUT_SUPERSEDED E_KC_SELF_LABEL E_KEY_UNKNOWN
E_LEDGER_EMPTY_SEARCH E_LOCATOR_INVALID E_NO_MATCH_INCOMPLETE
E_OBSERVED_PROVENANCE_MISMATCH E_OBSERVED_RAW_REQUIRED
E_OPTION_DISPOSITION_REQUIRED E_OPTION_INVALID E_OPTION_REQUIRED E_OPTION_SELECTION
E_OUTCOME_INVALID E_PATH_SYMLINK E_PROVENANCE_INVALID
E_PUBLISHED_AT_BASIS_INVALID E_RANDOMIZATION_INVALID E_RECOMMENDATION_INVALID
E_REF_DIGEST_MISMATCH E_REF_INVALID E_REF_MISSING E_REVISION_INVALID
E_ROLEPLAY_AS_OBSERVED E_SCHEMA_VERSION E_SCOPE_DELTA_INVALID
E_SOURCE_DIGEST_INVALID E_SOURCE_DIGEST_MISMATCH E_SOURCE_ENTRY_INVALID
E_SOURCE_FAMILY_INVALID E_SOURCE_GROUP_INVALID E_SOURCE_UNAVAILABLE_INVALID
E_STATUS_INVALID E_SUPERSEDES_INVALID E_TEXT_FORMAT E_TIMESTAMP_INVALID
E_TYPE_INVALID E_USER_REPORTED_AS_OBSERVED E_YAML_INVALID
'''.split())

def emit_summary(mode,result,exit_code,availability,value):
 print(json.dumps({'schema':SUMMARY_SCHEMA,'selection_mode':mode,'result':result,
                   'exit_code':exit_code,'diagnostics':{'availability':availability,'value':value}},
                  sort_keys=True,separators=(',',':')))

def main():
 ap=argparse.ArgumentParser(add_help=False)
 ap.add_argument('--root',required=True); group=ap.add_mutually_exclusive_group(required=True); group.add_argument('--artifact'); group.add_argument('--bundle'); group.add_argument('--files',nargs='+')
 ap.add_argument('--summary-json',action='store_true')
 ap.add_argument('--help',action='help')
 try: args=ap.parse_args()
 except SystemExit as e: return 0 if e.code==0 else 2
 mode='artifact' if args.artifact else 'files' if args.files else 'bundle'
 def early_result(code):
  if args.summary_json: emit_summary(mode,'NOT_MEASURED',code,'NOT_MEASURED',None)
  return code
 root=Path(args.root)
 if not root.is_absolute() or not root.is_dir() or root.is_symlink(): print('check-product-artifact: invalid --root',file=sys.stderr); return early_result(2)
 if root!=root.resolve(): print('check-product-artifact: --root must be canonical and symlink-free',file=sys.stderr); return early_result(2)
 root=root.resolve()
 def input_path(raw):
  candidate=Path(raw)
  if not candidate.is_absolute(): candidate=root/candidate
  try: rel=candidate.relative_to(root)
  except ValueError: return None
  if '..' in rel.parts: return None
  current=root
  for part in rel.parts:
   current=current/part
   if current.is_symlink(): return None
  return candidate
 if args.artifact:
  p=input_path(args.artifact)
  if p is None or not p.is_file(): print('check-product-artifact: invalid --artifact',file=sys.stderr); return early_result(2)
  files=[p]
 elif args.files:
  files=[]
  for raw in args.files:
   p=input_path(raw)
   if p is None or not p.is_file(): print('check-product-artifact: invalid --files entry',file=sys.stderr); return early_result(2)
   files.append(p)
  if len(set(files))!=len(files): print('check-product-artifact: duplicate --files entry',file=sys.stderr); return early_result(2)
 else:
  p=input_path(args.bundle)
  if p is None or not p.is_dir(): print('check-product-artifact: invalid --bundle',file=sys.stderr); return early_result(2)
  files=sorted((x for x in p.rglob('*.md') if not x.is_symlink()),key=lambda x:x.relative_to(root).as_posix().encode())
  symlinks=[x for x in p.rglob('*') if x.is_symlink()]
  if not files: print('check-product-artifact: empty bundle',file=sys.stderr); return early_result(1)
 checker=Checker(root)
 for x in symlinks if args.bundle else []: checker.add(x.relative_to(root).as_posix(),'E_PATH_SYMLINK')
 failed=checker.run(files,emit_text=not args.summary_json)
 code=1 if failed else 0
 if args.summary_json:
  diagnostics=set(checker.diags)
  counts={}
  known=all(item_code in SUMMARY_CODES for _,item_code in diagnostics)
  if known:
   for _,item_code in diagnostics: counts[item_code]=counts.get(item_code,0)+1
   emit_summary(mode,'FAIL' if failed else 'PASS',code,'MEASURED',{'count':len(diagnostics),'counts_by_code':dict(sorted(counts.items()))})
  else:
   emit_summary(mode,'FAIL',code,'NOT_MEASURED',None)
 return code
if __name__=='__main__': raise SystemExit(main())
