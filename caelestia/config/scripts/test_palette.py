from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import palette
import palette_backend as backend
import workflows as w


def entry(ident, label, **extra):
    return dict(id=ident, label=label, group='Windows', keys=['SUPER + X'], lua='hl.dsp.no_op()', **extra)


class PanelTests(unittest.TestCase):
    def model(self, entries, **kwargs):
        return backend.Model(entries=entries, active={'address':'0x1','title':'Test window'}, clients=[{'address':'0x1','mapped':True,'focusHistoryID':0}], **kwargs)

    def test_disabled_stock_actions_are_hidden(self):
        data=w.run(['lua',str(palette.BASE/'scripts/palette-vars.lua')])
        with patch.object(w,'run',return_value=data),patch.object(w,'ipc',return_value=[]):
            rows=palette.catalog(w)
        self.assertFalse(any(r['id'] in ('kbTodoWs','kbMusicWs') for r in rows))
        self.assertTrue(any(r['id']=='notes-search' for r in rows))

    def test_search_prefers_title_over_synonyms(self):
        title=entry('one','Open notes')
        synonym=entry('two','Another command',keywords='open notes')
        self.assertLess(backend.rank('open notes',title),backend.rank('open notes',synonym))
        self.assertEqual(backend.rank('SUPER+X',title),0)
        self.assertIsNone(backend.rank('nonexistent',title))

    def test_workspace_families_expand_only_when_needed(self):
        m=self.model([entry('kbGoToWs'+str(i),'Go to workspace '+str(i)) for i in range(1,11)])
        r=m.handle(dict(op='query',query='',category='Browse all'))
        self.assertEqual(len(r['rows']),1)
        self.assertEqual(r['rows'][0]['kind'],'family')
        r=m.handle(dict(op='activate',id=r['rows'][0]['id']))
        self.assertEqual(len(r['rows']),10)
        r=m.handle(dict(op='back'))
        self.assertEqual(r['view'],'commands')
        r=m.handle(dict(op='query',query='workspace 3',category='All'))
        self.assertEqual(r['rows'][0]['id'],'kbGoToWs3')

    def test_details_preserve_query_selection_and_scroll(self):
        m=self.model([entry('one','Open notes')])
        m.handle(dict(op='query',query='notes',category='All'))
        m.handle(dict(op='details',id='one',scroll=88))
        r=m.handle(dict(op='back'))
        self.assertEqual((r['query'],r['selected'],r['scroll']),('notes','one',88))

    def test_close_requires_explicit_confirmation_and_cancel_is_safe(self):
        m=self.model([entry('kbCloseWindow','Close focused window',confirm=True)])
        m.handle(dict(op='query',query='close',category='All'))
        r=m.handle(dict(op='activate',id='kbCloseWindow'))
        self.assertEqual(r['view'],'confirm')
        self.assertIn('Test window',r['detail']['confirmation'])
        r=m.handle(dict(op='activate',id='kbCloseWindow'))
        self.assertEqual(r['view'],'confirm')
        self.assertIsNone(m.pending)
        r=m.handle(dict(op='back'))
        self.assertEqual(r['query'],'close')

    def test_confirmed_action_waits_for_panel_to_hide(self):
        m=self.model([entry('kbCloseWindow','Close focused window',confirm=True)])
        m.handle(dict(op='query',query='close',category='All'))
        m.handle(dict(op='activate',id='kbCloseWindow'))
        with patch.object(m,'execute') as execute:
            r=m.handle(dict(op='activate',id='kbCloseWindow',confirmed=True))
            self.assertEqual(r['kind'],'execute');execute.assert_not_called()
            m.handle(dict(op='execute',id='kbCloseWindow'));execute.assert_called_once()

    def test_unavailable_previous_window(self):
        m=self.model([entry('previous','Focus previous window')])
        r=m.handle(dict(op='query',query='previous',category='All'))
        self.assertTrue(r['rows'][0]['disabled'])
        r=m.handle(dict(op='activate',id='previous'))
        self.assertEqual(r['kind'],'state');self.assertIsNone(m.pending)

    def test_unverified_binding_cannot_execute(self):
        m=self.model([dict(id='unknown:Q',label='Unknown',group='Other',keys=['SUPER+Q'])])
        m.handle(dict(op='query',query='unknown',category='All'))
        r=m.handle(dict(op='activate',id='unknown:Q'))
        self.assertTrue(r['detail']['reference'])
        with self.assertRaises(ValueError):m.handle(dict(op='execute',id='unknown:Q'))

    def test_notes_group_matches_and_escape_markup(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'notes';root.mkdir()
            (root/'Inbox.md').write_text('Docker <img src="file:///etc/passwd">\nDocker commands\nOther context')
            (root/'.hidden.md').write_text('Docker')
            outside=Path(temp)/'outside.md';outside.write_text('Docker')
            (root/'link.md').symlink_to(outside)
            m=self.model([],start='notes',notes_root=root)
            r=m.handle(dict(op='query',query='docker',category='All'))
            self.assertEqual(len(r['rows']),1)
            self.assertEqual(r['rows'][0]['hits'],[1,2])
            self.assertIn('&lt;img',r['rows'][0]['preview'])
            self.assertNotIn('<img',r['rows'][0]['preview'])

    def test_oversized_notes_are_disclosed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'large.md').write_text('x'*2000001)
            m=self.model([],start='notes',notes_root=root)
            self.assertIn('1 files omitted',m.snapshot()['notice'])


if __name__=='__main__':unittest.main()
