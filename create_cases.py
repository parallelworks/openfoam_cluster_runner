import json, sys, shutil, os


if __name__ == '__main__':
    cases_json = sys.argv[1]
    chdir = sys.argv[2]
    os.chdir(chdir)

    with open(cases_json, 'r') as f:
        cases = json.load(f)

    for ci,case in enumerate(cases['cases']):
        print('\nGenerating case {}'.format(ci+1))
        print('  Copying template directory <{template_dir}> to case directory <{case_dir}>'.format(
            template_dir = os.path.expanduser(cases['template_directory']),
            case_dir = case['directory']
        ))
        shutil.copytree(os.path.expanduser(cases['template_directory']), case['directory'])

        for fdict in case['files']:
            print('    Rewriting file {}'.format(fdict['path']))
            f = open(os.path.join(case['directory'], fdict['path']), mode='r')
            ftext = f.read()
            f.close()
            for param in fdict['parameters']:
                print('      Replacing placeholder <{}> with value <{}>'.format(param['placeholder'], str(param['value'])))
                ftext = ftext.replace(param['placeholder'], str(param['value']))

            f = open(os.path.join(case['directory'], fdict['path']), mode='w')
            f.write(ftext)
            f.close()

