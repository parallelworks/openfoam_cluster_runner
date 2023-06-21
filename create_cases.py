import json, sys, shutil, os, argparse


def read_args():
    parser = argparse.ArgumentParser()
    parsed, unknown = parser.parse_known_args()
    for arg in unknown:
        if arg.startswith(("-", "--")):
            parser.add_argument(arg, default="", nargs="?")
    args = vars(parser.parse_args())
    return args


if __name__ == '__main__':
    args = read_args()
    cases_json = args['cases_json']
    jobdir = args['jobdir']

    os.chdir(jobdir)

    with open(cases_json, 'r') as f:
        cases = json.load(f)

    template_directory = os.path.dirname(cases_json)

    for ci,case in enumerate(cases['cases']):
        print('\nGenerating case {}'.format(ci+1))
        print('  Copying template directory <{template_dir}> to case directory <{case_dir}>'.format(
            template_dir = os.path.expanduser(template_directory),
            case_dir = case['directory']
        ))
        shutil.copytree(os.path.expanduser(template_directory), case['directory'])

        for fdict in case['files']:
            print('    Rewriting file {}'.format(fdict['path']))
            f = open(os.path.join(case['directory'], fdict['path']), mode='r')
            ftext = f.read()
            f.close()
            for param in fdict['parameters']:
                placeholder = param['placeholder']
                value = str(param['value'])
                if placeholder in args:
                    value = args[placeholder].replace('___', ' ')
                print('      Replacing placeholder <{}> with value <{}>'.format(placeholder, value))
                ftext = ftext.replace(placeholder, value)

            f = open(os.path.join(case['directory'], fdict['path']), mode='w')
            f.write(ftext)
            f.close()

