import datetime as dt
import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('prepare_workbook',Path(__file__).parents[1]/'scripts/prepare-workbook.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class WorkbookMigrationTests(unittest.TestCase):
 def test_excel_serial_rounds_to_the_original_second(self):
  self.assertEqual(m.excel_clock('46324.33509259259'),(dt.time(8,2,32),dt.date(2026,10,29)))
 def test_overnight_is_not_invented_for_time_only_exit(self):
  r=m.timeline('46323','0.7','0.6',dt.date(2026,10,29))
  self.assertIsNone(r['exit_at']);self.assertEqual(r['legacy']['exit_time'],'14:24:00')
  self.assertTrue(any('anterior' in i for i in r['issues']))
 def test_unknown_date_never_becomes_today(self):
  r=m.timeline('(S/ Data)','0.5','0.6',dt.date(2026,10,29))
  self.assertIsNone(r['entry_at']);self.assertIsNone(r['exit_at']);self.assertFalse(r['legacy']['open_at_import'])
 def test_full_timestamps_preserve_an_explicit_next_day_exit(self):
  r=m.timeline('46323','46323.9','46324.1',dt.date(2026,10,29))
  self.assertEqual(r['exit_at'],'2026-10-29T02:24:00-03:00');self.assertFalse(r['issues'])
 def test_only_today_with_a_blank_exit_is_open(self):
  for date,exit_value,opened in [('46324','',True),('46323','',False),('46324','OPERATOR NAME',False)]:
   self.assertEqual(m.timeline(date,'0.4',exit_value,dt.date(2026,10,29))['legacy']['open_at_import'],opened)
 def test_multiple_plates_and_placeholders_are_not_concatenated(self):
  self.assertEqual(m.plate('ABC-1234'),'ABC1234')
  self.assertEqual(m.plate('ABC1234 E DEF5678'),'ABC1234 E DEF5678')
  self.assertEqual(m.plate('xxx-yyy'),'XXX-YYY')
 def test_source_identity_and_sql_quoting(self):
  self.assertEqual(m.source_key('123.0'),'123');self.assertEqual(m.source_key('0012ab'),'0012ab')
  self.assertEqual(m.uid('record:test:1'),m.uid('record:test:1'))
  self.assertIn("D''ÁGUA",m.sql_literal({'name':"D'ÁGUA"}))

if __name__=='__main__':unittest.main()
