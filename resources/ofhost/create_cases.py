import json, shutil, os


if __name__ == '__main__':
    with open('inputs.json') as inputs_json:
        form_inputs = json.load(inputs_json)

    openfoam_inputs = form_inputs['openfoam']
    cases_json = os.path.join(openfoam_inputs['case_dir'], 'cases.json')
    jobdir = form_inputs['resource']['jobdir']

    os.chdir(jobdir)

    with open(cases_json, 'r') as f:
        cases = json.load(f)

    template_directory = os.path.dirname(cases_json)

    for ci,case in enumerate(cases['cases']):
        print('\nGenerating case {}'.format(ci+1))
        print(json.dumps(case, indent = 4))
        print('  Copying template directory <{template_dir}> to case directory <{case_dir}>'.format(
            template_dir = os.path.expanduser(template_directory),
            case_dir = case['directory']
        ))
        shutil.copytree(os.path.expanduser(template_directory), case['directory'])
        for fi,fdict in enumerate(case['files']):
            print('    Rewriting file {}'.format(fdict['path']))
            f = open(os.path.join(case['directory'], fdict['path']), mode='r')
            ftext = f.read()
            f.close()
            for pi, param in enumerate(fdict['parameters']):
                placeholder = param['placeholder']
                value = str(param['value'])
                if placeholder in openfoam_inputs:
                    value = str(openfoam_inputs[placeholder]).replace('___', ' ')
                    case['files'][fi]['parameters'][pi]['value'] = value
                print('      Replacing placeholder <{}> with value <{}>'.format(placeholder, value))
                ftext = ftext.replace(placeholder, value)

            f = open(os.path.join(case['directory'], fdict['path']), mode='w')
            f.write(ftext)
            f.close()
        
        # Save updated case JSON with the case parameters in each case directory
        with open(os.path.join(case['directory'], 'case.json'), 'w') as f:
            json.dump(case, f, indent = 4)
        
        # Remove cases.json with all the cases from each case directory
        os.remove(os.path.join(case['directory'], 'cases.json')) 

