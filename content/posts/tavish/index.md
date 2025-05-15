---
title: "Streamlining My Job Search With AI*"
description: "Tavish - my AI Job Search assistant"
summary: "Dipping my toes into GenAI finally with DeepSeek, Ollama, and open-webui."
author: ["Whit Huntley"]
date: 1745602100
draft: true
links-as-notes: true
papersize: A4
showReadingTime: true
tags: ["relevant"]
---

Recently, the job search has gone from "difficult" to "problematic" to "downright catastrophic". This is partially due to the raw number of applicants limited hiring pool, but also due unfortunately to the integration of ML into the process. In a better world this might not be such a bad thing: better processing of more data could allow applicants with the best fit to reach interviews and skip the faff of the initial submission. Unfortunately, what has actually happened is "AI (buzzword)" gets shoehorned haphazardly into places it doesn't belong and creates new inane hoops for applicants to jump through.

With the increasing amount of work required per-application, I decided the only sensible approach was to throw my hat into the arms race.

# Approach

Unfortunately technological advancements have made the job search even more obtuse and tedious. Given the sheer volume of job listings, I decided to enter into the arms race employers and recruiters have been at the top of for years; a guerilla war of employment if you will. In the same way applicant tracking systems immediately bin some grotesque majority of applicants, I would automatically bin a majority of job listings. In fear of sounding a bit *Butlerian Jihad*: I refuse to degrade myself by spending all of my time trying to convince a machine I am worthy of it. Less ideologically, here are my goals:

- Filter the torrent of job listings that LinkedIn/Seek/Indeed/Glassdoor/whatever else *think* I match into a trickle of good opportunities (both in terms of my own professional development and my utility to the potential employer).
- Make that first machine deal with its own kind.
    - Although this doesn't apply when I trust my application is guaranteed to be reviewed by a human.
- Allow me to actually spend time with keenly focusing on each application.

My second point has that caveat because my enemy isn't the employer itself -- although I will admit even the best application process is frustrating and stressful -- but the disparity between the minutes or hours of human work required to craft a good application and the potential 0 seconds of human work involved in reviewing it[^1]. I understand companies get hundreds if not thousands of applications for any given job listing, but a resume is built for humans -- even 30 seconds under review by a human hiring manager is more fair than "`your application was under the minimum keyword count and has been rejected. die.`"

[^1]: This does mean everything I say here goes out the window in the few times recruiters reach out to me first; I'm never going to go "thanks for submitting your interest, I'll get back to you between tomorrow and never about my candidacy".

# Implementations

Due to the amount of text data and my curiosity to join a bandwagon, I felt solving these problems was a viable function of an LLM. Not as in "AI will solve everything" but because comparing some textual representation of my accomplishments and a job description is a workload actually perfect for a (sophisticated) predict-the-next-word program. The system needs an understanding of who "I" am/what I've done, a job listing, and to compare the two and calculate how much of the latter is a subset of the former.

1. **Hosted** Use an online model with context fed using a "CV"[^2]. This is the most plug-n-play approach, but is limited by how general its results will be.
    - Pros:
        - Best performance/speed - Does not require doing something terrible to my home desktop and I assume the output will be superior given the exponentially greater number of parameters a datacenter instance has than some sod on her 5 year old desktop could hope for.
        - Minimal work - All I would need is a good, general purpose prompt.
    - Cons:
        - Non-exhaustive; there are only so many tokens I can feed even the best hosted model before it truncates a file.
        - Privacy; there are certain things I wouldn't feed a hosted model in case it gets trained on highly intimate data.
2. **Self-Hosted**: Self-host a publicly available model and give it context of me by way of a knowledge base. This is a midpoint between options 1 and 3, and gives me a comprehensive high-level overview of the backing tech in the process, without getting too much into the weeds.
    - Pros:
        - *More specific results* - while the speed or quality will not match a hosted version, the amount of personal data it can take advantage of is far higher.
        - *Better integration* - Future iterations of a self-hosted approach could allow me to build tools on top of it, such as a browser extension that could give me a score without having to tab out (a hosted approach could do this too, but not without costing a couple bucks).
    - Cons:
        - Limited personal hardware - I use an old RX 5700 XT because I like when Linux works. Unfortunately this will mean far worse results than even an Nvidia GPU of the same generation (much less any card more modern). Furthermore, it's known to freeze up (often taking my computer with it) when playing more intensive video games, and I'm sure running an LLM will cause a similar strain.
        - Prerequisite work - unlike the hosted counterpart where I only have to make a single good CV, the data I want a self-hosted option to use requires extensive pruning and pre-sorting.
3. **Wholly Custom**: Develop a hybrid approach which is exactly tuned for this kind of job.
    - Pros:
        - Utility - A well-implemented approach could perform this task more accurately and use fewer resources than either the ob
        - Public viability - A well-implemented approach could be made available to others, either to self-host and/or a hosted version potentially commercialized.
    - Cons:
        - Complexity - I feel like if it's *too* custom I'd be better served going back to university and pursuing a second degree in mathematics.
        - Initial work - far more than data filtering, this would require actually getting in the weeds and making something. Even if this works I would be spending months in development to still have the job hunt take weeks.

[^2]: I say "CV" but I realize what I have isn't really a "*Curriculum Vitae*" in the strictest sense, but rather an exhaustive, 5+ page resume.

## Hosted

I started using a hosting solution to test my broad idea, and  it working can be built on or used (I needed a CV anyway). The LLM I chose was DeepSeek-R1; after a (rather casual) comparison against Claude, DeepSeek tended to be more accurate (ChatGPT was not considered due to highly restrictive upload limits on the free plan). I use LibreOffice writer so I export my CV as an XML file which is what I upload. The prompt gives me a fitness score between elements on my CV and the job listing, along with pointers for drafting a cover letter.

I have created about a dozen applications using this, here's roughly what my process looked like:

1. Initially skim through each listing, looking for the summary and disqualifying factors (e.g. "5+ years experience" or "we cannot sponsor visas at this time" [for NZ-based jobs]). This data tends to be in the first ~3 lines and the final third (which is mostly bullet points). This takes around 15 seconds per-listing.
2. If I don't see that, I will feed the job description into Tavish. Sometimes listings end up putting the disqualifying factors somewhere outside the above places, and Tavish catches them. Using the result I determine if I want to consider applying: 60% for US jobs, 90%  for NZ jobs. This takes about 30-45 seconds depending on how long it wants to think.
3. This is the first time I actually read the listing properly. If I think it's a good fit, then I will send in a submission and make an entry on my job spreadsheet.
    - If asked to draft a cover letter, I use a cover letter template which predates this idea in conjunction with the key ideas Tavish gave to me and my own reading. I know I could automate the cover letter process too, but as it's something generally read by humans, I don't feel the need to 

{{< details summary="Prompt" >}}

Note that the `${VARIABLES}` are manually populated; they're included to show what *would* go there. I understand this demonstration does not *super* work if I don't populate the actual job listing, but I don't want to name companies just in case someone does not like the idea I have used AI, even if tangentially related, to my job listing.

> [Today is ${DATE}] Given my attached CV and the following job description, please evaluate my fitness for the position (think carefully and be realistic. I would rather be told no more than waste my time on a very likely rejection). Give a fitness rating between my CV and the job description as a percentage and explain your verdict.
> 
> I have given you my complete CV and the full job listing. Do not make claims about either if you cannot directly cite them.
> 
> - I am applying for entry-level positions.
> - If and only if the position is based in New Zealand you must take into consideration that I will require a visa to work, whereas other candidates may not. Note this in the reasoning but it should not affect the fitness rating itself (as the rating is solely between my CV and the job); the exception to this is if the job description states outright it will not support a visa, then the fitness is 0%.
> - If the position asks for than 3+ years of professional experience with any given technology I am not a good fit (however an argument might be made for <3 years if I have enough highly relevant personal or academic work).
> - There must be a strong match between a majority of skills on the job listing and my CV.
> - There is a certain flexibility regarding technologies listed and similar items on my CV, but consider the overlap between the two more holistically rather than expecting 100% exact matches. Many skills are at least partially transferable.
> 
> If and only if you think I should apply, please also provide specific, relevant, and extremely brief feedback for drafting the cover letter in 1-3 sentences.
> 
> ```
> Job Listing Title: "${COPY_PASTE}"
> Company: ${COPY_PASTE}
> Location: ${COPY_PASTE}
> ---
> ${COPY_PASTE}
> ```

{{</ details >}}

{{< details summary="Example Result" >}}

> **Fitness Rating**: 85%
> 
> **Verdict**:
> 
> Your CV strongly aligns with `[REDACTED]`'s Junior Software Engineer role. The position explicitly requires no prior professional experience, focusing instead on a bachelor's degree (which you are completing imminently), authorization to work in the US (which you have), and demonstrable foundational technical skills. Your academic projects (e.g., JAWS, AskHole) and self-hosted Kubernetes cluster showcase hands-on coding, collaboration, and cloud-native development—directly relevant to responsibilities like writing code, Agile teamwork, and SDLC toolchain usage. While the job emphasizes training in technologies like .NET/Java (not explicitly on your CV), your proficiency in Go, Python, and infrastructure automation demonstrates adaptability to learn new stacks. Certifications (Security+, Network+) further reinforce your technical foundation. The GPA (~2.99) is slightly below a 3.0 but unlikely to disqualify given the role’s focus on potential over prior experience.
> 
> **Cover Letter Feedback**:
> - Highlight your project leadership (e.g., JAWS backend architecture, Agile collaboration) and self-driven technical initiatives (Kubernetes cluster, CI/CD automation) to emphasize adaptability and problem-solving. 
> - Mention your readiness to leverage `[REDACTED]`'s training to expand into .NET/Java ecosystems, bridging academic rigor with real-world application.

{{</ details >}}

## Self-Hosted

A previous iteration of this plan populated a knowledge base with every git commits I authored by way of diffs, but it didn't work.

{{< alert "circle-info" >}} 
P.S.: I am *very* hirable btw. Please don't hesitate to [reach out](mailto:hello@whits.io).
{{</ alert >}}